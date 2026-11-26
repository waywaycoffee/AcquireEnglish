const { API_BASE } = require('./config')
const auth = require('./auth')

function request({ url, method = 'GET', data, authRequired = false }) {
  const header = {
    'Content-Type': 'application/json',
  }
  const token = auth.getToken()
  if (token) {
    header.Authorization = `Bearer ${token}`
  } else if (authRequired) {
    return Promise.reject(new Error('请先登录'))
  }

  return new Promise((resolve, reject) => {
    wx.request({
      url: url.startsWith('http') ? url : `${API_BASE}${url}`,
      method,
      data,
      header,
      success(res) {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(res.data)
          return
        }
        if (res.statusCode === 401) {
          auth.clearSession()
        }
        const detail =
          (res.data && (res.data.detail || res.data.message)) ||
          `HTTP ${res.statusCode}`
        reject(new Error(typeof detail === 'string' ? detail : JSON.stringify(detail)))
      },
      fail(err) {
        reject(new Error(err.errMsg || '网络错误'))
      },
    })
  })
}

module.exports = {
  request,
}
