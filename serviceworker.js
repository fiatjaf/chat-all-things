/* globals self, caches, fetch, Headers, Response, Blob, randomColor */

self.importScripts('https://cdnjs.cloudflare.com/ajax/libs/randomcolor/0.4.4/randomColor.min.js')

self.addEventListener('install', function (e) {
  console.log('INSTALL', e)
  e.waitUntil(
    caches.open('VENDOR')
    .then(cache =>
      cache.addAll([
        'https://code.ionicframework.com/ionicons/2.0.1/css/ionicons.min.css',
        'https://cdnjs.cloudflare.com/ajax/libs/pouchdb/6.0.6/pouchdb.min.js',
        'https://wzrd.in/standalone/pouchdb-ensure',
        'https://cdnjs.cloudflare.com/ajax/libs/cuid/1.3.8/browser-cuid.min.js'
      ]))
    .then(() => self.skipWaiting())
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
  var parts = e.request.url.split('/')
  /*if (e.request.url.slice(-4) === '.png') {
    e.respondWith(
      Promise.resolve(new Response(
        new Blob([`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" style=" background: ${randomColor()};"><g backgroundcolor="rgba(134,53,53,1)"></g></svg>`]),
        {
          status: 200,
          headers: new Headers({
            'Content-Type': 'image/svg'
          })
        }
      ))
    )
  } else */if (parts.length === 5 && parts[3] === 'channel') {
    // at any URL like https://site.com/channel/<channel-name>, we serve index.html
    e.respondWith(
      fetch('/index.html', {mode: 'no-cors'})
    )
  } else {
    e.respondWith(
      caches.open('VENDOR')
      .then(cache =>
        cache.match(e.request)
        .then(matching => matching || Promise.reject('no-match'))
      )
      .catch(() => fetch(e.request))
    )
  }
})

self.addEventListener('message', function (e) {
})
