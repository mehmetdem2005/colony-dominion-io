package io.colonydominion.identity;

import android.app.Activity;
import android.os.CancellationSignal;
import android.util.Base64;

import androidx.annotation.NonNull;
import androidx.core.content.ContextCompat;
import androidx.credentials.Credential;
import androidx.credentials.CredentialManager;
import androidx.credentials.CredentialManagerCallback;
import androidx.credentials.CustomCredential;
import androidx.credentials.GetCredentialRequest;
import androidx.credentials.GetCredentialResponse;
import androidx.credentials.exceptions.GetCredentialCancellationException;
import androidx.credentials.exceptions.GetCredentialException;

import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption;
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Locale;
import java.util.concurrent.Executor;

/**
 * Android identity boundary for the game.
 *
 * The primary path is Credential Manager's native Google account chooser. It
 * returns an ID token to Godot, which is exchanged with Supabase server-side.
 * No browser OAuth path exists on Android. Tokens and nonces are never logged
 * and are cleared after Godot consumes them.
 */
public final class ColonyGoogleIdentity extends GodotPlugin {
    public static final int STATE_IDLE = 0;
    public static final int STATE_PENDING = 1;
    public static final int STATE_SUCCESS = 2;
    public static final int STATE_CANCELLED = 3;
    public static final int STATE_UNAVAILABLE = 4;
    public static final int STATE_ERROR = 5;

    private final Object stateLock = new Object();
    private final SecureRandom secureRandom = new SecureRandom();

    private int state = STATE_IDLE;
    private int generation = 0;
    private String idToken = "";
    private String rawNonce = "";
    private String errorCode = "";
    private CancellationSignal cancellationSignal;

    public ColonyGoogleIdentity(Godot godot) {
        super(godot);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "ColonyGoogleIdentity";
    }

    @UsedByGodot
    public boolean isNativeSignInAvailable() {
        return getActivity() != null;
    }

    @UsedByGodot
    public boolean startNativeSignIn(final String webClientId) {
        final Activity activity = getActivity();
        if (activity == null || webClientId == null || webClientId.trim().isEmpty()) {
            failImmediately(STATE_UNAVAILABLE, "native_identity_not_configured");
            return false;
        }

        final int requestGeneration;
        final String requestRawNonce;
        final CancellationSignal requestCancellation = new CancellationSignal();
        synchronized (stateLock) {
            if (state == STATE_PENDING) {
                return false;
            }
            generation += 1;
            requestGeneration = generation;
            requestRawNonce = generateNonce();
            state = STATE_PENDING;
            idToken = "";
            rawNonce = requestRawNonce;
            errorCode = "";
            cancellationSignal = requestCancellation;
        }

        activity.runOnUiThread(() -> {
            try {
                final String hashedNonce = sha256Hex(requestRawNonce);
                final GetSignInWithGoogleOption googleOption =
                        new GetSignInWithGoogleOption.Builder(webClientId.trim())
                                .setNonce(hashedNonce)
                                .build();
                final GetCredentialRequest request = new GetCredentialRequest.Builder()
                        .addCredentialOption(googleOption)
                        .build();
                final CredentialManager credentialManager = CredentialManager.create(activity);
                final Executor mainExecutor = ContextCompat.getMainExecutor(activity);

                credentialManager.getCredentialAsync(
                        activity,
                        request,
                        requestCancellation,
                        mainExecutor,
                        new CredentialManagerCallback<GetCredentialResponse, GetCredentialException>() {
                            @Override
                            public void onResult(GetCredentialResponse response) {
                                consumeCredential(requestGeneration, response);
                            }

                            @Override
                            public void onError(@NonNull GetCredentialException error) {
                                final boolean cancelled =
                                        error instanceof GetCredentialCancellationException;
                                finishFailure(
                                        requestGeneration,
                                        cancelled ? STATE_CANCELLED : STATE_UNAVAILABLE,
                                        cancelled ? "user_cancelled" : safeExceptionCode(error)
                                );
                            }
                        }
                );
            } catch (Exception error) {
                finishFailure(requestGeneration, STATE_UNAVAILABLE, safeExceptionCode(error));
            }
        });
        return true;
    }

    @UsedByGodot
    public int getSignInState() {
        synchronized (stateLock) {
            return state;
        }
    }

    @UsedByGodot
    public String consumeIdToken() {
        synchronized (stateLock) {
            final String value = idToken;
            idToken = "";
            return value;
        }
    }

    @UsedByGodot
    public String consumeRawNonce() {
        synchronized (stateLock) {
            final String value = rawNonce;
            rawNonce = "";
            return value;
        }
    }

    @UsedByGodot
    public String getSignInError() {
        synchronized (stateLock) {
            return errorCode;
        }
    }

    @UsedByGodot
    public void resetSignIn() {
        synchronized (stateLock) {
            generation += 1;
            if (cancellationSignal != null) {
                cancellationSignal.cancel();
            }
            cancellationSignal = null;
            state = STATE_IDLE;
            idToken = "";
            rawNonce = "";
            errorCode = "";
        }
    }

    @UsedByGodot
    public void cancelNativeSignIn() {
        synchronized (stateLock) {
            if (state != STATE_PENDING) {
                return;
            }
            generation += 1;
            if (cancellationSignal != null) {
                cancellationSignal.cancel();
            }
            cancellationSignal = null;
            state = STATE_CANCELLED;
            idToken = "";
            rawNonce = "";
            errorCode = "user_cancelled";
        }
    }

    private void consumeCredential(int requestGeneration, GetCredentialResponse response) {
        try {
            final Credential credential = response.getCredential();
            if (!(credential instanceof CustomCredential)) {
                finishFailure(requestGeneration, STATE_ERROR, "unexpected_credential_type");
                return;
            }
            final CustomCredential customCredential = (CustomCredential) credential;
            if (!GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL.equals(
                    customCredential.getType())) {
                finishFailure(requestGeneration, STATE_ERROR, "unexpected_credential_type");
                return;
            }
            final GoogleIdTokenCredential googleCredential =
                    GoogleIdTokenCredential.createFrom(customCredential.getData());
            final String token = googleCredential.getIdToken();
            if (token == null || token.length() < 128) {
                finishFailure(requestGeneration, STATE_ERROR, "invalid_google_id_token");
                return;
            }
            synchronized (stateLock) {
                if (generation != requestGeneration || state != STATE_PENDING) {
                    return;
                }
                state = STATE_SUCCESS;
                idToken = token;
                errorCode = "";
                cancellationSignal = null;
            }
        } catch (Exception error) {
            finishFailure(requestGeneration, STATE_ERROR, safeExceptionCode(error));
        }
    }

    private void finishFailure(int requestGeneration, int failureState, String code) {
        synchronized (stateLock) {
            if (generation != requestGeneration || state != STATE_PENDING) {
                return;
            }
            state = failureState;
            idToken = "";
            rawNonce = "";
            errorCode = code;
            cancellationSignal = null;
        }
    }

    private void failImmediately(int failureState, String code) {
        synchronized (stateLock) {
            generation += 1;
            state = failureState;
            idToken = "";
            rawNonce = "";
            errorCode = code;
            cancellationSignal = null;
        }
    }

    private String generateNonce() {
        final byte[] bytes = new byte[32];
        secureRandom.nextBytes(bytes);
        return Base64.encodeToString(bytes, Base64.NO_WRAP | Base64.URL_SAFE | Base64.NO_PADDING);
    }

    private static String sha256Hex(String value) throws Exception {
        final byte[] digest = MessageDigest.getInstance("SHA-256")
                .digest(value.getBytes(StandardCharsets.UTF_8));
        final StringBuilder result = new StringBuilder(digest.length * 2);
        for (byte item : digest) {
            result.append(String.format(Locale.US, "%02x", item & 0xff));
        }
        return result.toString();
    }

    private static String safeExceptionCode(Exception error) {
        final String simpleName = error.getClass().getSimpleName();
        return simpleName == null || simpleName.isEmpty()
                ? "native_identity_error"
                : simpleName;
    }
}
