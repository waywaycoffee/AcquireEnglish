const { OPEN_APP_URL, DOWNLOAD_URL } = require('./config')

/**
 * 引导打开 App：复制深链 + 提供官网中间页 / 下载页链接。
 * （小程序内不能直接拉起第三方 App；需用户到系统浏览器打开。）
 */
function openApp(path = 'home', query = {}) {
  const qs = Object.keys(query)
    .map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(query[k])}`)
    .join('&')
  const scheme = `acquireenglish://${path}${qs ? `?${qs}` : ''}`
  const guide =
    `${OPEN_APP_URL}?path=${encodeURIComponent(path)}` + (qs ? `&${qs}` : '')

  wx.showActionSheet({
    itemList: ['复制「打开 App」引导链接', '复制下载页', '复制 App 深链'],
    success(res) {
      const map = [guide, DOWNLOAD_URL, scheme]
      const data = map[res.tapIndex]
      if (!data) return
      wx.setClipboardData({
        data,
        success() {
          wx.showModal({
            title: '已复制',
            content:
              res.tapIndex === 1
                ? '请到系统浏览器粘贴打开下载页安装。'
                : '请到系统浏览器粘贴打开；微信内置浏览器可能无法拉起 App。',
            showCancel: false,
          })
        },
      })
    },
  })
}

module.exports = {
  openApp,
}
