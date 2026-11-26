const { API_BASE } = require('./utils/config')
const auth = require('./utils/auth')

App({
  globalData: {
    apiBase: API_BASE,
    user: null,
  },

  onLaunch() {
    const token = auth.getToken()
    if (token) {
      auth.fetchMe().then((user) => {
        this.globalData.user = user
      }).catch(() => {
        auth.clearSession()
      })
    }
  },
})
