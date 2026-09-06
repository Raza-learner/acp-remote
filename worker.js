export default {
  async fetch(req, env) {
    const url = new URL(req.url)
    const branch = url.pathname.endsWith('/dev') ? 'dev' : 'main'

    const ext = url.pathname.startsWith('/install.ps1') ? 'ps1' : 'sh'
    if (url.pathname.startsWith('/install.' + ext) || (ext === 'sh' && (url.pathname === '/install' || url.pathname === '/install/'))) {
      const isDev = branch === 'dev'
      const relayUrl = isDev
        ? 'wss://runmote-relay.onrender.com/daemon'
        : 'wss://runmote-relay-u2zi.onrender.com/daemon'
      const token = isDev
        ? (env.ACP_DAEMON_TOKEN_DEV || '')
        : (env.ACP_DAEMON_TOKEN_MAIN || '')

      const gh = `https://raw.githubusercontent.com/Raza-learner/Runmote/${branch}/scripts/install.${ext}`
      const headers = { 'User-Agent': 'runmote-worker' }
      if (env.GITHUB_TOKEN) headers['Authorization'] = `Bearer ${env.GITHUB_TOKEN}`
      const resp = await fetch(gh, { headers })
      let text = await resp.text()
      // Inject relay config from Worker secrets (no hardcoded tokens in source code)
      text = text.replaceAll('__ACP_RELAY_URL__', relayUrl)
      text = text.replaceAll('__ACP_DAEMON_TOKEN__', token)
      return new Response(text, {
        headers: {
          'content-type': ext === 'ps1' ? 'text/powershell' : 'text/x-shellscript',
          'cache-control': 'public, max-age=60'
        }
      })
    }

    return new Response('Not found', { status: 404 })
  },

  // Keep Render free-tier relays awake (sleep after 15 min inactivity)
  async scheduled(event, env, ctx) {
    await fetch('https://runmote-relay-u2zi.onrender.com/health')
    await fetch('https://runmote-relay.onrender.com/health')
  }
}
