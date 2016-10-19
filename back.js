/* globals Elm, runElmProgram, PouchDB, cuid */

// run elm app
var app
try {
  app = Elm.App.fullscreen({
    me: 'fiatjaf',
    channel: 'taproah'
  })
} catch (e) {
  var stylesheets = document.querySelectorAll('link')
  for (var i = 0; i < stylesheets.length; i++) {
    stylesheets[i].parentNode.removeChild(stylesheets[i])
  }
  runElmProgram()
}

// setup database
var db = new PouchDB('main')

var userPictures = {
  _id: '_design/user-pictures',
  version: 1,
  views: {
    'user-pictures': {
      map: `function (doc) {
        if (doc._id.split('-')[0] === 'user' && doc.pictureURL) {
          emit(doc.name, doc.pictureURL)
        }
      }`
    }
  }
}
db.get('_design/user-pictures', (err, ddoc) => {
  if (err) {
    db.put(userPictures)
  } else if (ddoc.version !== userPictures.version) {
    userPictures._rev = ddoc._rev
    db.put(userPictures)
  }
})
setTimeout(() => db.viewCleanup(), 5000)

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
  switch (doc.type) {
    case 'message':
      doc._id = 'message-' + cuid()
      break
    case 'card':
      doc._id = 'card-' + cuid()
      break
    default: return
  }
  delete doc.type
  db.put(doc)
  .then(() => app.ports.cardLoaded.send(doc))
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

db.changes({
  live: true,
  include_docs: true,
  return_docs: false
}).on('change', function (change) {
  switch (change.doc._id.split('-')[0]) {
    case 'message':
      app.ports.pouchMessages.send(change.doc)
      break
    case 'card':
      app.ports.pouchCards.send(change.doc)
      break
  }
}).on('error', function (err) {
  console.log('pouchdb changes error:', err)
})

// service worker
if (navigator.serviceWorker) {
  navigator.serviceWorker.register('/serviceworker.js')
  .then(reg => {
    db.query('user-pictures')
    .then(res => {
      res.rows.map(row => {
        navigator.serviceWorker.controller.postMessage(row)
      })
    })
  })
}
