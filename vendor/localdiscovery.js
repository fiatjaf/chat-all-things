/* eslint-disable no-unused-vars */
/* global WebSocket, RTCPeerConnection */

const port = 9999

function localWebSocket () {
  return LANIP()
  .then(localips => new Promise(function (resolve, reject) {
    for (var l = 0; l < localips.length; l++) {
      var local = localips[l]
      var components = local.split('.')
      var our = components[3]
      var base = components.slice(0, 3)

      function tryAddress (i) {
        var address = 'ws://' + base.concat(i).join('.') + ':' + port
        try {
          var ws = new WebSocket(address)
          ws.onopen = function () {
            console.log('GOT A RESULT', address, ws)
            // found a suitable websocket
            resolve(address)
            ws.close()
          }
          ws.onclose = ws.onerror = function () {}
        } catch (e) {}
      }

      var i
      for (i = our; i > 0; i--) { tryAddress(i) }
      for (i = our + 1; i <= 254; i++) { tryAddress(i) }

      setTimeout(reject, 7000)
    }
  }))
}

function LANIP () {
  return new Promise(function (resolve, reject) {
    if (window.RTCPeerConnection) {
      var rtc = new RTCPeerConnection({iceServers: []})
      if (1 || window.mozRTCPeerConnection) {
        // FF [and now Chrome!] needs a channel/stream to proceed
        rtc.createDataChannel('', {reliable: false})
      }

      rtc.onicecandidate = function (evt) {
        // convert the candidate to SDP so we can run it through our general parser
        // see https://twitter.com/lancestout/status/525796175425720320 for details
        if (evt.candidate) grepSDP('a=' + evt.candidate.candidate)
      }
      rtc.createOffer(function (offerDesc) {
        grepSDP(offerDesc.sdp)
        rtc.setLocalDescription(offerDesc)
      }, function (e) { console.warn('offer failed', e) })

      var addrs = {}
      setTimeout(function () {
        delete addrs['0.0.0.0']
        var ips = Object.keys(addrs)
        if (ips.length) {
          resolve(ips)
        } else {
          reject('no local ips found')
        }
      }, 500)

      function grepSDP (sdp) {
        var hosts = []
        sdp.split('\r\n').forEach(function (line) {
          // c.f. http://tools.ietf.org/html/rfc4566#page-39

          var parts, addr
          if (~line.indexOf('a=candidate')) {
            // http://tools.ietf.org/html/rfc4566#section-5.13
            parts = line.split(' ') // http://tools.ietf.org/html/rfc5245#section-15.1
            addr = parts[4]
            var type = parts[7]
            if (type === 'host') {
              addrs[addr] = true
            }
          } else if (~line.indexOf('c=')) {
            // http://tools.ietf.org/html/rfc4566#section-5.7
            parts = line.split(' ')
            addr = parts[2]
            addrs[addr] = true
          }
        })
      }
    } else {
      reject('no webrtc capabilities')
    }
  })
}
