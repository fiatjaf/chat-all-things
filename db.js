/* eslint-disable no-unused-vars */
/* globals app, appready */

const PouchDB = window.PouchDB
const haiku = window.haiku
const localStorage = window.localStorage
const PouchReplicator = window.PouchReplicator
const md5 = require('pouchdb-md5').stringMd5
const throttleit = require('throttleit')

const allChannels = require('./init').allChannels


// setup database
PouchDB.debug.enable('*')
PouchDB.plugin(require('pouchdb-ensure'))
const dbname = 'channel-' + window.channelConfig.name
var db = window.db = new PouchDB(dbname)
setTimeout(() => db.viewCleanup(), 5000)
module.exports.db = db


// setup webrtc channel management and pouchdb channelManager
function ChannelManager () {
  this.connections = {}
  this.replicators = {}

  this.set = function (otherMachineId, connName, datachannel) {
    var replicator = this.replicators[otherMachineId] = this.replicators[otherMachineId] ||
      new PouchReplicator('replicator', PouchDB, db, {batch_size: 50})

    replicator.addPeer(connName, datachannel)

    var connections = this.connections[otherMachineId] = this.connections[otherMachineId] || {}
    connections[connName] = datachannel

    replicator.on('endpeerreplicate', function () {
      for (var i in replicator.datachannels) {
        var dc = replicator.datachannels[i]
        dc.send('<received>')
      }
      app.ports.replication.send([otherMachineId, '<received>'])
    })

    datachannel.addEventListener('message', e => {
      console.log(connName + ' says: ' + e.data)
      if (e.data === '<received>') {
        app.ports.replication.send([otherMachineId, '<sent>'])
        db.compact()
      }
    })
  }

  this.cleanup = function (otherMachineId, connName) {
    var replicator = this.replicators[otherMachineId]
    if (!replicator) return
    replicator.removePeer(connName)
  }

  this.replicate = function () {
    console.log('replicating pouchdb to', Object.keys(this.replicators))
    for (var otherMachineId in this.replicators) {
      console.log('> replicating pouchdb to', otherMachineId)

      app.ports.replication.send([otherMachineId, '<replicating>'])

      var replicator = this.replicators[otherMachineId]
      replicator.replicate()
    }
  }
}
module.exports.channelManager = new ChannelManager()


// mark this channel as existing.
// one doc in the database is sufficient to consider it existent.
db.allDocs({limit: 1, startkey: 'A'})
.then(res => {
  if (res.rows.length) {
    allChannels[window.channelConfig.name] = true
    localStorage.setItem(
      'allChannels',
      JSON.stringify(allChannels)
    )
  }
})


// get information about the current user and pass it to the app
db.allDocs({startkey: 'user-', endkey: 'user-{', include_docs: true})
.then(res => {
  if (res.rows.length === 0) {
    // do nothing.
  } else if (res.rows.length === 1) {
    app.ports.currentUser.send(res.rows[0].doc)
  } else {
    var lastUserName = localStorage.getItem('lastuser-' + window.channelConfig.name)
    if (lastUserName) {
      var found = res.rows.find(row => row.doc.name === lastUserName)
      if (found) {
        app.ports.currentUser.send(found.doc)
      }
    }
  }
})


// listen for db changes and react accordingly
appready(() => {
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
        break
    }
  }).on('error', function (err) {
    console.log('pouchdb changes error:', err)
  })
})


// setup card search
PouchDB.plugin(require('pouchdb-quick-search'))
var searchdb
var emit // satisfying eslint
var mapfun = function (doc) {
  if (doc._id.split('-')[0] === 'card') {
    if (doc.name) {
      emit(null, {id: doc._id, n: doc.name}) // name
    }

    for (var i = 0; i < doc.contents.length; i++) {
      var content = doc.contents[i]
      if (typeof content === 'string') {
        emit(null, {id: doc._id, c: content}) // content
      } else if (content.text) {
        emit(null, {id: doc._id, m: content.text}) // message
      }
    }
  }
}.toString()
db.ensure({
  _id: '_design/cardsearch',
  views: {
    cardsearch: {
      map: mapfun
    }
  }
})
.then(() => {
  db.query('cardsearch')
  searchdb = new PouchDB(dbname + '-mrview-' + md5(mapfun + 'undefined' + 'undefined'))
})
appready(() => {
  app.ports.searchCard.subscribe(throttleit(function (searchquery) {
    var termcount = searchquery.split(/ +/g).length

    searchdb.search({
      query: searchquery,
      fields: {
        'value.n': 5,
        'value.c': 4,
        'value.m': 2
      },
      include_docs: true,
      mm: parseInt(100 / termcount) + '%'
    })
    .then(res => {
      return db.allDocs({keys: res.rows.map(row => row.doc.value.id), include_docs: true})
    })
    .then(res => {
      app.ports.searchedCard.send(res.rows.map(row => row.doc))
    })
    .catch(e => console.log('search failed', e))
  }), 400)
})
