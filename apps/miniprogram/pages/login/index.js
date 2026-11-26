const auth = require('../../utils/auth')

Page({
  data: {
    loading: false,
    error: '',
  },

  onLogin() {
    if (this.data.loading) return
    this.setData({ loading: true, error: '' })
    auth
      .loginWithWx()
      .then(() => {
        wx.showToast({ title: '登录成功', icon: 'success' })
        setTimeout(() => {
          wx.switchTab({ url: '/pages/home/index' })
        }, 400)
      })
      .catch((err) => {
        this.setData({
          loading: false,
          error: (err && err.message) || '登录失败',
        })
      })
      .finally(() => {
        this.setData({ loading: false })
      })
  },
})
