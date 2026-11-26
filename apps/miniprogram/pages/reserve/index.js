const auth = require('../../utils/auth')
const { request } = require('../../utils/api')

function parseBilibili(url) {
  const text = (url || '').trim()
  const bv = text.match(/BV[\w]+/i)
  if (!bv) return null
  const pageMatch = text.match(/[?&]p=(\d+)/i)
  return {
    bvid: bv[0],
    page: pageMatch ? Number(pageMatch[1]) : 1,
  }
}

Page({
  data: {
    url: '',
    message: '',
    items: [],
  },

  onShow() {
    this.refresh()
  },

  onInput(e) {
    this.setData({ url: e.detail.value })
  },

  refresh() {
    if (!auth.getToken()) {
      this.setData({ items: [], message: '登录后可查看预约' })
      return
    }
    request({ url: '/api/shared-subtitles/reservations?mine=1', authRequired: true })
      .then((body) => {
        this.setData({ items: (body && body.items) || [], message: '' })
      })
      .catch((err) => {
        this.setData({
          items: [],
          message: (err && err.message) || '列表暂不可用',
        })
      })
  },

  submit() {
    if (!auth.getToken()) {
      wx.navigateTo({ url: '/pages/login/index' })
      return
    }
    const parsed = parseBilibili(this.data.url)
    if (!parsed) {
      this.setData({ message: '请粘贴含 BVxxxx 的 B 站链接' })
      return
    }
    this.setData({ message: '提交中…' })
    request({
      url: '/api/shared-subtitles/jobs',
      method: 'POST',
      authRequired: true,
      data: {
        bvid: parsed.bvid,
        page: parsed.page,
        reserve: true,
      },
    })
      .then(() => {
        this.setData({ message: '已入队', url: '' })
        this.refresh()
      })
      .catch((err) => {
        this.setData({ message: (err && err.message) || '提交失败' })
      })
  },
})
