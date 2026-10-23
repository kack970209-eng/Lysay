// 公开页面：首页、隐私政策、服务条款（Google OAuth 品牌设定与 App Store 都需要）

function layout(title: string, body: string): string {
  return `<!doctype html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>
  body { margin: 0; font: 16px/1.7 -apple-system, BlinkMacSystemFont, "PingFang TC", "Microsoft JhengHei", sans-serif;
         background: #000; color: #f5f5f7; }
  main { max-width: 760px; margin: 0 auto; padding: 48px 24px 80px; }
  h1 { font-size: 34px; margin: 0 0 8px; }
  h2 { font-size: 20px; margin: 32px 0 8px; }
  p, li { color: #d1d1d6; }
  a { color: #0a84ff; }
  .sub { color: #98989d; }
  nav { margin-top: 40px; display: flex; gap: 20px; }
</style>
</head>
<body><main>${body}
<nav><a href="/">Lysay</a><a href="/privacy">隱私權政策</a><a href="/terms">服務條款</a></nav>
</main></body></html>`;
}

export const HOME_HTML = layout("Lysay 語音輸入", `
<h1>Lysay</h1>
<p class="sub">iOS AI 語音輸入法</p>
<p>Lysay 是一款 iOS 輸入法：邊說邊出字，說完後由手機本地的 AI 整理成通順的文字；同時提供注音輸入、剪貼簿記錄與收藏資料夾。
所有語音辨識與 AI 整理都在手機上離線完成。</p>
<p>聯絡我們：<a href="mailto:kack970209@gmail.com">kack970209@gmail.com</a></p>
`);

export const PRIVACY_HTML = layout("Lysay 隱私權政策", `
<h1>隱私權政策</h1>
<p class="sub">最後更新：2026 年 10 月 23 日</p>

<h2>語音與輸入內容</h2>
<p>Lysay 的語音辨識與 AI 整理全部在你的手機本地執行。你的語音、說話內容與鍵盤輸入的文字不會上傳到我們的伺服器，也不會提供給任何第三方。</p>

<h2>帳號資料</h2>
<p>當你使用 Apple 或 Google 登入時，我們只會取得登入服務提供的帳號識別碼、電子郵件與名字，用來建立你的 Lysay 帳號、記錄 AI 語音使用時數與訂閱方案。</p>

<h2>剪貼簿同步</h2>
<p>登入後，你在 Lysay 中的剪貼簿記錄與收藏資料夾會同步到我們的伺服器（Cloudflare），只用於讓你在不同裝置上取用自己的資料。未登入時，這些資料只保存在你的手機上。</p>

<h2>資料刪除</h2>
<p>你可以在 App 的「我的帳號」中刪除帳號，我們會刪除你的帳號資料與所有同步內容。也可以來信要求刪除。</p>

<h2>聯絡我們</h2>
<p><a href="mailto:kack970209@gmail.com">kack970209@gmail.com</a></p>
`);

export const TERMS_HTML = layout("Lysay 服務條款", `
<h1>服務條款</h1>
<p class="sub">最後更新：2026 年 10 月 23 日</p>

<h2>服務內容</h2>
<p>Lysay 提供 iOS 輸入法，包括 AI 語音輸入、注音輸入與剪貼簿功能。注音輸入與剪貼簿功能免費使用；AI 語音輸入每個帳號提供 4 小時免費額度，之後需訂閱 Lysay Pro。</p>

<h2>訂閱</h2>
<p>Lysay Pro 依方案（月付或年付）計費，期滿後需續訂。方案價格以 App 內顯示為準。</p>

<h2>使用規範</h2>
<p>請勿以任何方式濫用、破解或干擾服務。我們可以停用違反規範的帳號。</p>

<h2>免責聲明</h2>
<p>AI 語音辨識與整理結果可能有誤，請在送出前自行確認內容。</p>

<h2>聯絡我們</h2>
<p><a href="mailto:kack970209@gmail.com">kack970209@gmail.com</a></p>
`);
