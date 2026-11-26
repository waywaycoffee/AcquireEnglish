/** API base — production ECS. DevTools 可在 local 改成内网地址。 */
const API_BASE = 'https://acquireenglish.curlhairai.com'

/** 打开 App 的 https 中间页（公众号 / 小程序外链共用） */
const OPEN_APP_URL = `${API_BASE}/open-app.html`

/** 官网下载页 */
const DOWNLOAD_URL = `${API_BASE}/download.html`

module.exports = {
  API_BASE,
  OPEN_APP_URL,
  DOWNLOAD_URL,
}
