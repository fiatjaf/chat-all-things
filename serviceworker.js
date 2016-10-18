/* globals self, caches, fetch */

self.addEventListener('install', function (e) {
  console.log('INSTALL', e)
  e.waitUntil(
    self.skipWaiting()
  )
})

self.addEventListener('activate', function (e) {
  console.log('ACTIVATE', e)
  e.waitUntil(
    caches.keys()
    .then(keyList =>
      Promise.all(keyList.map(key => {
        return caches.delete(key)
      }))
    ).then(self.clients.claim())
  )
})

self.addEventListener('fetch', function (e) {
  console.log('FETCH', e.request.url)
  var parts = e.request.url.split('/')
  var last = parts.slice(-2)[1]
  if (parts.slice(-2)[0] === 'user' && last.slice(-4) === '.png') {
    e.respondWith(
      caches.open('USER-PICTURES')
      .then(cache =>
        cache.match(e.request.url)
        .then(resp => {
          if (resp) {
            return resp
          } else {
            return fetch('https://api.adorable.io/avatars/140/' + last.slice(0, -4) + '.png', {mode: 'no-cors'})
            .then(response => {
              cache.put(e.request.url, response.clone())
              return response.clone()
            })
          }
        })
      )
    )
  } else {
    e.respondWith(fetch(e.request))
  }
})

self.addEventListener('message', function (e) {
  e.waitUntil(
    // receive picture URLs from pouchdb, fetch and cache them
    caches.open('USER-PICTURES')
    .then(cache => {
      return cache.match('user/' + e.data.key + '.png')
      .then(cached => {
        if (!cached) {
          fetch(e.data.value)
          .then(r => new Promise(function (resolve) {
            setTimeout(() => resolve(r), 1000)
          }))
          .then(response => {
            cache.put('user/' + e.data.key + '.png', response)
          })
        }
      })
    })
  )
})
