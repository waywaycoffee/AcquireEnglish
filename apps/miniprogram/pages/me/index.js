const auth = require('../../utils/auth')
const { openApp } = require('../../utils/openApp')
const { DOWNLOAD_URL } = require('../../utils/config')

Page({
  data: {
    loggedIn: false,
    user: {},
  },

  onShow() {
    const user = auth.getUser() || {}
    this.setData({
      loggedIn: !!auth.getToken(),
      user,
    })
    if (auth.getToken()) {
      auth.fetchMe().then((u) => this.setData({ user: u || {} })).catch(() => {})
    }
  },

  goLogin() {
    wx.navigateTo({ url: '/pages/login/index' })
  },

  logout() {
    auth.clearSession()
    this.setData({ loggedIn: false, user: {} })
    wx.showToast({ title: '已退出', icon: 'none' })
  },

  openApp() {
    openApp('home')
  },

  copyDownload() {
    wx.setClipboardData({ data: DOWNLOAD_URL })
  },
})
