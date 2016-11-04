/* globals app, okready Elm, runElmProgram,
    localStorage */


// first thing: register service worker
if (navigator.serviceWorker) {
  navigator.serviceWorker.register('/serviceworker.js')
}


const WebTorrent = window.WebTorrent
const dragDrop = require('drag-drop')
const cuid = window.cuid

const machineId = require('./init').machineId
const allChannels = require('./init').allChannels
const db = require('./db').db
const channelManager = require('./db').channelManager


// run elm app
var ok
try {
  window.app = Elm.App.fullscreen({
    machineId: machineId,
    channel: window.channelConfig,
    allChannels: Object.keys(allChannels)
  })
  ok = true
} catch (e) {
  var stylesheets = document.querySelectorAll('link')
  for (var i = 0; i < stylesheets.length; i++) {
    stylesheets[i].parentNode.removeChild(stylesheets[i])
  }
  runElmProgram()
  ok = false
}
if (ok) okready()


function replicate () {
  channelManager.replicate()
}


// elm app ports
app.ports.updateCardContents.subscribe(function (data) {
  var id = data[0]
  var index = data[1]
  var value = data[2]
  db.get(id, function (err, card) {
    if (err) {
      console.log('failed to fetch', id, 'to update', err)
    } else {
      if (index === -1) {
        // special case for updating the card name
        if (card.name !== value) {
          card.name = value
          db.put(card)
            .then(replicate)
        }
      } else if (value === null) {
        // deleting a content
        if (card.contents[index]) {
          card.contents.splice(index, 1)
          db.put(card)
            .then(replicate)
        }
      } else if (typeof card.contents[index] === 'undefined') {
        // adding content (either text or conversation)
        card.contents.push(value)
        db.put(card)
          .then(replicate)
      } else if (card.contents[index] !== value) {
        // updating text content
        card.contents[index] = value
        db.put(card)
          .then(replicate)
      }
    }
  })
})

app.ports.pouchCreate.subscribe(function (doc) {
  if (doc.author && (doc.text || doc.torrent)) {
    doc._id = 'message-' + cuid()
  } else if ('name' in doc && doc.contents) {
    doc._id = 'card-' + cuid()
  } else {
    console.log('got invalid pouchCreate:', doc)
    return
  }

  delete doc.type
  db.put(doc)
    .then(replicate)
  .then(() => {
    if (doc._id.split('-')[0] === 'card') app.ports.cardLoaded.send(doc)
  })
})
app.ports.deleteCard.subscribe(function (id) {
  db.get(id, function (err, doc) {
    if (err) {
      console.log('could not get doc to delete:', id)
    } else {
      db.remove(doc)
    }
  })
})
app.ports.loadCard.subscribe(function (id) {
  db.get(id, function (err, doc) {
    if (err) {
      console.log('could not get doc', id)
    } else {
      app.ports.cardLoaded.send(doc)
    }
  })
})
app.ports.setUserPicture.subscribe(function (data) {
  var name = data[0]
  var pictureURL = data[1]
  var userId = `user-${machineId}-${name}`

  db.get(userId)
  .catch(() => {
    // if the new user is being created, we should select him
    localStorage.setItem('lastuser-' + window.channelConfig.name, name)

    return {
      _id: userId,
      name: name,
      machineId: machineId
    }
  })
  .then(doc => {
    doc.pictureURL = pictureURL
    return db.put(doc)
             .then(replicate)
  })
  .catch(e => console.log('failed to save user with picture', e))
})

app.ports.userSelected.subscribe(function (name) {
  localStorage.setItem('lastuser-' + window.channelConfig.name, name)
})
app.ports.focusField.subscribe(function (selector) {
  setTimeout(function () {
    document.querySelector(selector).focus()
  }, 1)
})
app.ports.scrollChat.subscribe(function (timeout) {
  setTimeout(function () {
    document.getElementById('messages').scrollTop = 99999
  }, timeout)
})
app.ports.deselectText.subscribe(function (timeout) {
  setTimeout(function () {
    if (document.selection) {
      document.selection.empty()
    } else if (window.getSelection) {
      window.getSelection().removeAllRanges()
    }
  }, timeout)
})


// webtorrent
var client = new WebTorrent()

setTimeout(function () {
  dragDrop('#chat', function (files) {
    client.seed(files, function (torrent) {
      var tInfo = torrentInfo(torrent)
      tInfo.progress = 1
      app.ports.droppedFileChat.send(tInfo)
    })
  })
}, 350)

app.ports.downloadTorrent.subscribe(function (data) {
  var messageId = data[0]
  var tInfo = data[1]
  client.add(tInfo.magnet, function (torrent) {
    torrent.files.forEach(file => {
      file.getBlobUrl(function (err, url) {
        if (err) return console.log('failed to fetch blob url', err)
        tInfo = torrentInfo(torrent)
        tInfo.files[file.name].blobURL = url
        app.ports.torrentInfo.send([messageId, tInfo])
      })
    })
    torrent.on('download', () => { app.ports.torrentInfo.send([messageId, torrentInfo(torrent)]) })
    torrent.on('upload', () => { app.ports.torrentInfo.send([messageId, torrentInfo(torrent)]) })
    torrent.on('noPeers', () => { app.ports.torrentInfo.send([messageId, torrentInfo(torrent)]) })
  })
})

function torrentInfo (t, fetching) {
  var files = {}
  t.files.forEach(f => {
    files[f.name] = {
      name: f.name,
      length: f.length
    }
  })

  return {
    magnet: t.magnetURI,
    files: files,
    downloaded: t.downloaded,
    progress: t.progress,
    uploaded: t.uploaded,
    numPeers: t.numPeers
  }
}
