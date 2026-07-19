import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "jose";
import type { Context, Next } from "hono";

const supabaseUrl = (process.env.SUPABASE_URL ?? "").replace(/\/$/, "");
const jwks = supabaseUrl
  ? createRemoteJWKSet(new URL(`${supabaseUrl}/auth/v1/.well-known/jwks.json`))
  : null;

export type AuthVariables = {
  auth: JWTPayload;
};

export async function requireSupabaseAuth(
  c: Context<{ Variables: AuthVariables }>,
  next: Next,
): Promise<Response | void> {
  if (!jwks || !supabaseUrl) {
    return c.json({ error: "SUPABASE_URL is not configured" }, 503);
  }
  const authorization = c.req.header("authorization") ?? "";
  const token = authorization.startsWith("Bearer ")
    ? authorization.slice("Bearer ".length)
    : "";
  if (!token) return c.json({ error: "Missing bearer token" }, 401);
  try {
    const verified = await jwtVerify(token, jwks, {
      issuer: `${supabaseUrl}/auth/v1`,
    });
    c.set("auth", verified.payload);
    await next();
  } catch {
    return c.json({ error: "Invalid or expired access token" }, 401);
  }
}
