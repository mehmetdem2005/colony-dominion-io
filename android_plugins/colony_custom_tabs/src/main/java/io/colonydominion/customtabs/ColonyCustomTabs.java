package io.colonydominion.customtabs;

import android.app.Activity;
import android.net.Uri;

import androidx.annotation.NonNull;
import androidx.browser.customtabs.CustomTabsIntent;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

/**
 * Minimal Godot Android plugin that opens a URL in an in-app Chrome Custom Tab.
 *
 * Google blocks OAuth inside a raw WebView (disallowed_useragent), so the only
 * Google-approved "in-app" sign-in surface is a Custom Tab: it overlays the game
 * in the same task and returns automatically when the user finishes, instead of
 * switching to the external browser app.
 *
 * The plugin registers as the Engine singleton "ColonyCustomTabs". GDScript calls
 * openCustomTab(url); if it returns false (or the singleton is absent, e.g. on
 * desktop) the caller falls back to OS.shell_open.
 */
public class ColonyCustomTabs extends GodotPlugin {

    public ColonyCustomTabs(Godot godot) {
        super(godot);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "ColonyCustomTabs";
    }

    @UsedByGodot
    public boolean isAvailable() {
        return getActivity() != null;
    }

    @UsedByGodot
    public boolean openCustomTab(final String url) {
        final Activity activity = getActivity();
        if (activity == null || url == null || url.isEmpty()) {
            return false;
        }
        try {
            activity.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    CustomTabsIntent intent = new CustomTabsIntent.Builder()
                            .setShowTitle(true)
                            .setUrlBarHidingEnabled(true)
                            .build();
                    intent.launchUrl(activity, Uri.parse(url));
                }
            });
            return true;
        } catch (Exception error) {
            return false;
        }
    }
}
