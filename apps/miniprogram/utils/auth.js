const { API_BASE } = require('./config')

const TOKEN_KEY = 'ae_mp_token'
const USER_KEY = 'ae_mp_user'

function getToken() {
  return wx.getStorageSync(TOKEN_KEY) || ''
}

function getUser() {
  return wx.getStorageSync(USER_KEY) || null
}

function setSession(token, user) {
  wx.setStorageSync(TOKEN_KEY, token || '')
  if (user) {
    wx.setStorageSync(USER_KEY, user)
  }
}

function clearSession() {
  wx.removeStorageSync(TOKEN_KEY)
  wx.removeStorageSync(USER_KEY)
  const app = getApp()
  if (app) {
    app.globalData.user = null
  }
}

function fetchMe() {
  const token = getToken()
  if (!token) {
    return Promise.reject(new Error('未登录'))
  }
  return new Promise((resolve, reject) => {
    wx.request({
      url: `${API_BASE}/api/auth/me`,
      method: 'GET',
      header: { Authorization: `Bearer ${token}` },
      success(res) {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          setSession(token, res.data)
          resolve(res.data)
          return
        }
        reject(new Error((res.data && res.data.detail) || '获取用户失败'))
      },
      fail(err) {
        reject(new Error(err.errMsg || '网络错误'))
      },
    })
  })
}

/** 微信小程序登录 → 后端 jscode2session → JWT */
function loginWithWx() {
  return new Promise((resolve, reject) => {
    wx.login({
      success(loginRes) {
        if (!loginRes.code) {
          reject(new Error('wx.login 未返回 code'))
          return
        }
        wx.request({
          url: `${API_BASE}/api/auth/wechat/mp-login`,
          method: 'POST',
          header: { 'Content-Type': 'application/json' },
          data: {
            code: loginRes.code,
            device_label: 'wechat-miniprogram',
          },
          success(res) {
            if (res.statusCode >= 200 && res.statusCode < 300 && res.data) {
              const token = res.data.access_token || res.data.token
              if (!token) {
                reject(new Error('登录响应缺少 token'))
                return
              }
              setSession(token, res.data.user || null)
              fetchMe()
                .then((user) => {
                  const app = getApp()
                  if (app) app.globalData.user = user
                  resolve({ token, user })
                })
                .catch(() => resolve({ token, user: res.data.user || null }))
              return
            }
            const detail =
              (res.data && res.data.detail) || `登录失败 HTTP ${res.statusCode}`
            reject(new Error(typeof detail === 'string' ? detail : JSON.stringify(detail)))
          },
          fail(err) {
            reject(new Error(err.errMsg || '网络错误'))
          },
        })
      },
      fail(err) {
        reject(new Error(err.errMsg || 'wx.login 失败'))
      },
    })
  })
}

module.exports = {
  getToken,
  getUser,
  setSession,
  clearSession,
  fetchMe,
  loginWithWx,
}
