const html = String.raw`<!doctype html>
<html lang="tr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover" />
  <meta name="theme-color" content="#0b0d0d" />
  <title>Colony Dominion.io — E-posta doğrulama</title>
  <style>
    :root {
      color-scheme: dark;
      font-family: Inter, Roboto, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #090b0b;
      color: #f4f2e9;
    }
    * { box-sizing: border-box; }
    body {
      min-height: 100vh;
      margin: 0;
      display: grid;
      place-items: center;
      padding: max(24px, env(safe-area-inset-top)) 20px max(24px, env(safe-area-inset-bottom));
      background:
        radial-gradient(circle at 50% 16%, rgba(241, 184, 59, .14), transparent 38%),
        linear-gradient(180deg, #111514 0%, #090b0b 100%);
    }
    main {
      width: min(100%, 520px);
      padding: 34px 28px 30px;
      border: 1px solid #3a4140;
      border-radius: 24px;
      background: rgba(18, 21, 21, .98);
      box-shadow: 0 24px 80px rgba(0, 0, 0, .52);
      text-align: center;
    }
    .mark {
      width: 72px;
      height: 72px;
      margin: 0 auto 22px;
      display: grid;
      place-items: center;
      border-radius: 22px;
      border: 2px solid #f1b83b;
      background: rgba(241, 184, 59, .12);
      color: #f1b83b;
      font-size: 36px;
      font-weight: 800;
    }
    .eyebrow {
      margin: 0 0 10px;
      color: #f1b83b;
      font-size: 12px;
      font-weight: 800;
      letter-spacing: .14em;
      text-transform: uppercase;
    }
    h1 { margin: 0 0 14px; font-size: clamp(27px, 7vw, 36px); line-height: 1.12; }
    p { margin: 0; color: #b8bfba; font-size: 16px; line-height: 1.65; }
    .detail {
      margin-top: 20px;
      padding: 14px 16px;
      border-radius: 14px;
      border: 1px solid #394140;
      background: #0d1010;
      color: #dfe3dd;
    }
    button {
      width: 100%;
      min-height: 56px;
      margin-top: 22px;
      border: 1px solid #ffd06b;
      border-radius: 14px;
      background: #f1b83b;
      color: #17130a;
      font: inherit;
      font-weight: 800;
      cursor: pointer;
    }
    small { display: block; margin-top: 16px; color: #7f8984; line-height: 1.5; }
    html[data-state="error"] .mark {
      border-color: #ff7469;
      background: rgba(255, 116, 105, .1);
      color: #ff7469;
    }
    html[data-state="error"] .eyebrow { color: #ff7469; }
    html[data-state="error"] button {
      border-color: #ff9b93;
      background: #ff7469;
      color: #220a08;
    }
  </style>
</head>
<body>
  <main>
    <div class="mark" id="mark" aria-hidden="true">✓</div>
    <p class="eyebrow">COLONY DOMINION ID</p>
    <h1 id="title">E-posta adresin doğrulandı</h1>
    <p id="message">Hesabın etkinleştirildi. Oyuna geri dön ve hesap ekranından <strong>Giriş Yap</strong> düğmesine dokun.</p>
    <p class="detail" id="detail">Bu sayfada şifre veya kişisel bilgi istenmez.</p>
    <button type="button" id="close">OYUNA GERİ DÖN</button>
    <small>Tarayıcı sekmeyi kapatamazsa geri tuşunu kullanabilirsin.</small>
  </main>
  <script>
    (() => {
      const query = new URLSearchParams(location.search);
      const hash = new URLSearchParams(location.hash.replace(/^#/, ""));
      const error = query.get("error_description") || hash.get("error_description") || query.get("error") || hash.get("error");
      if (error) {
        document.documentElement.dataset.state = "error";
        document.getElementById("mark").textContent = "!";
        document.getElementById("title").textContent = "Doğrulama tamamlanamadı";
        document.getElementById("message").textContent = "Bağlantının süresi dolmuş veya daha önce kullanılmış olabilir.";
        document.getElementById("detail").textContent = decodeURIComponent(error.replace(/\+/g, " "));
      } else {
        document.documentElement.dataset.state = "success";
      }
      document.getElementById("close").addEventListener("click", () => {
        window.close();
        history.back();
      });
    })();
  </script>
</body>
</html>`;

Deno.serve((request: Request): Response => {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method Not Allowed", {
      status: 405,
      headers: { Allow: "GET, HEAD" },
    });
  }
  return new Response(request.method === "HEAD" ? null : html, {
    status: 200,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store, max-age=0",
      "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
      "x-frame-options": "DENY",
    },
  });
});
