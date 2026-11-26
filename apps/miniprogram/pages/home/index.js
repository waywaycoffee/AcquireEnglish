const auth = require('../../utils/auth')
const { openApp } = require('../../utils/openApp')
const { request } = require('../../utils/api')

Page({
  data: {
    loggedIn: false,
    dueCount: '—',
    doneCount: '—',
    streakDays: '—',
    studyMinutes: '—',
    reserveActive: '—',
  },

  onShow() {
    this.refresh()
  },

  refresh() {
    const loggedIn = !!auth.getToken()
    this.setData({ loggedIn })
    if (!loggedIn) {
      this.setData({
        dueCount: '—',
        doneCount: '—',
        streakDays: '—',
        studyMinutes: '—',
        reserveActive: '—',
      })
      return
    }
    request({ url: '/api/review/today-summary', authRequired: true })
      .then((s) => {
        this.setData({
          dueCount: s.due_count ?? 0,
          doneCount: s.done_count ?? 0,
          streakDays: s.streak_days ?? 0,
          studyMinutes: s.study_minutes_today ?? 0,
        })
      })
      .catch(() => {
        // API 未上线时保持占位，不打断首页
        this.setData({
          dueCount: 0,
          doneCount: 0,
          streakDays: 0,
          studyMinutes: 0,
        })
      })
    request({ url: '/api/shared-subtitles/reservations?mine=1', authRequired: true })
      .then((body) => {
        const items = (body && body.items) || []
        const active = items.filter((it) =>
          ['queued', 'running', 'pending', 'processing'].includes(
            String(it.status || '').toLowerCase(),
          ),
        ).length
        this.setData({ reserveActive: active })
      })
      .catch(() => this.setData({ reserveActive: 0 }))
  },

  goReview() {
    wx.switchTab({ url: '/pages/review/index' })
  },

  goReserve() {
    wx.switchTab({ url: '/pages/reserve/index' })
  },

  goOral() {
    wx.navigateTo({ url: '/pages/oral/index' })
  },

  goLogin() {
    wx.navigateTo({ url: '/pages/login/index' })
  },

  openApp() {
    openApp('home')
  },
})
