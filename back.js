/* globals Elm, runElmProgram, PouchDB, cuid, location, localStorage, pouchdbEnsure */

var machineId = localStorage.getItem('machineId')
if (!machineId) {
  machineId = cuid.slug()
  localStorage.setItem('machineId', machineId)
}

var channelName = location.pathname.split('/').slice(-1)[0]


// setup database
PouchDB.plugin(pouchdbEnsure)
var db = new PouchDB('channel-' + channelName)
setTimeout(() => db.viewCleanup(), 5000)


// one doc in the database is sufficient to mark this channel as existing
var allChannels = JSON.parse(localStorage.getItem('allChannels') || '{}')
db.allDocs({limit: 1, startkey: 'A'})
.then(res => {
  if (res.length) {
    allChannels[channelName] = true
    localStorage.setItem(
      'allChannels',
      JSON.stringify(allChannels)
    )
  }
})


// run elm app
var app
try {
  app = Elm.App.fullscreen({
    machineId: machineId,
    channel: channelName,
    allChannels: Object.keys(allChannels)
  })
} catch (e) {
  var stylesheets = document.querySelectorAll('link')
  for (var i = 0; i < stylesheets.length; i++) {
    stylesheets[i].parentNode.removeChild(stylesheets[i])
  }
  runElmProgram()
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
        }
      } else if (value === null) {
        // deleting a content
        if (card.contents[index]) {
          card.contents.splice(index, 1)
          db.put(card)
        }
      } else if (typeof card.contents[index] === 'undefined') {
        // adding content (either text or conversation)
        card.contents.push(value)
        db.put(card)
      } else if (card.contents[index] !== value) {
        // updating text content
        card.contents[index] = value
        db.put(card)
      }
    }
  })
})

app.ports.pouchCreate.subscribe(function (doc) {
  if (doc.author && doc.text) {
    doc._id = 'message-' + cuid()
  } else if (doc.name && doc.contents) {
    doc._id = 'card-' + cuid()
  } else {
    return
  }

  delete doc.type
  db.put(doc)
  .then(() => {
    if (doc._id.split('-')[0] === 'card') app.ports.cardLoaded.send(doc)
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
  .catch(() => ({
    _id: userId,
    name: name,
    machineId: machineId
  }))
  .then(doc => {
    doc.pictureURL = pictureURL
    return db.put(doc)
  })
  .catch(e => console.log('failed to save user with picture', e))
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


// listen for db changes
db.changes({
  live: true,
  include_docs: true,
  return_docs: false
}).on('change', function (change) {
  if (change.doc._deleted) {
    return
  }

  switch (change.doc._id.split('-')[0]) {
    case 'message':
      app.ports.pouchMessages.send(change.doc)
      break
    case 'card':
      app.ports.pouchCards.send(change.doc)
      break
    case 'user':
      app.ports.pouchUsers.send(change.doc)

      // also update the user picture cache
      if (change.doc.pictureURL) {
        navigator.serviceWorker.controller.postMessage({
          key: change.doc.name,
          value: change.doc.pictureURL
        })
      }
      break
  }
}).on('error', function (err) {
  console.log('pouchdb changes error:', err)
})


// get information about the current user
db.allDocs({startkey: 'user-', endkey: 'user-{', include_docs: true})
.then(res => {
  if (res.rows.length === 0) {
    // do nothing.
  } else if (res.rows.length === 1) {
    app.ports.currentUser.send(res.rows[0].doc)
  } else {
    var lastUserName = localStorage.getItem('lastuser-' + channelName)
    if (lastUserName) {
      var user = res.rows.find(row => row.doc.name === lastUserName)
      if (user) {
        app.ports.currentUser.send(user)
      }
    }
  }
})


// register service worker
if (navigator.serviceWorker) {
  navigator.serviceWorker.register('/serviceworker.js')
}
