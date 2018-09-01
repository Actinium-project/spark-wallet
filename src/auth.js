import fs from 'fs'
import assert from 'assert'
import basicAuth from 'basic-auth'
import nanoid from 'nanoid'
import nanogen from 'nanoid/generate'
import cookieParser from 'cookie-parser'
import {createHmac} from 'crypto'

const cookieAge = 2592000000 // 1 month

const hmacStr = (key, data) => createHmac('sha256', key).update(data).digest('base64').replace(/\W+/g, '')

module.exports = (app, loginFile, login, _accessKey) => {
  if (loginFile && (login || _accessKey)) throw new Error('--login-file cannot be used with --login or --access-key')

  let username, password

  const hasFile = loginFile && fs.existsSync(loginFile)
  if (hasFile) {
    console.log(`Loading login credentials from ${loginFile}`)
    [ username, password, _accessKey ] = fs.readFileSync(loginFile).toString('utf-8').trim().split(':')
    assert(password, `Invalid login file at ${loginFile}, expecting "username:pwd[:access-key]"`)
  } else if (login) { // provided via --login (or LOGIN)
    [ username, password ] = login.split(':', 2)
    assert(password, `Invalid login format, expecting "username:pwd"`)
  } else { // generate random
    username = nanogen('abcdefghijklmnopqrstuvwxyz', 5)
    password = nanoid(15)
    console.log(`No LOGIN or --login specified, picked username "${username}" with password "${password}"`)
  }

  // HMAC derive the access key from the user/pwd combo, if not explicitly defined
  const accessKey   = _accessKey || hmacStr(`${username}:${password}`, 'access-key')
      , manifestKey = hmacStr(accessKey, 'manifest-key').substr(0, 10)
      , manifestRe  = new RegExp(`^/manifest-${manifestKey}/`)
      , cookieKey   = hmacStr(accessKey, 'cookie-key')
      , cookieOpt   = { signed: true, httpOnly: true, sameSite: true, secure: app.enabled('tls'), maxAge: cookieAge }

  if (loginFile && !hasFile) {
    console.log(`Writing login credentials to ${loginFile}`)
    fs.writeFileSync(loginFile, [ username, password, accessKey ].join(':'))
  }

  Object.assign(app.settings, { manifestKey, accessKey })

  app.use(cookieParser(cookieKey))

  return (req, res, next) => {
    // The manifest.json file has to be accessible without basic auth headers and without cookies.
    // This allow accessing the /manifest/ directory by including the `manifestKey` in the path.
    // Note that the manifestKey grants access _only_ to the manifest.
    if (req.method === 'GET' && manifestRe.test(req.url)) {
      req.url = req.url.replace(manifestRe, '/manifest/')
      return next()
    }

    // Authenticate using the access key token, via the X-Access header or access-key query string argument.
    // This also marks the request as csrfSafe. Used for RPC API calls and for SSE requests.
    if (req.get('X-Access') === accessKey || req.query['access-key'] === accessKey) {
      req.csrfSafe = true
      if (req.path == '/') res.cookie('user', username, cookieOpt)
      return next()
    }

    // Authenticate with HMAC-signed cookies
    if (req.signedCookies.user) {
      return next()
    }

    // HTTP basic authentication (username/password)
    const cred = basicAuth(req)
    if (cred && cred.name === username && cred.pass === password) {
      // Once the user authenticates with basic auth, set a signed cookie to authenticate future requests.
      // HTTP basic auth is quirky, this makes for a smoother experience.
      res.cookie('user', username, cookieOpt)
      return next()
    }

    res.set('WWW-Authenticate', 'Basic realm="Private Area"')
       .sendStatus(401)
  }
}
