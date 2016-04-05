_                   = require 'lodash'
async               = require 'async'
http                = require 'http'
SubscriptionManager = require 'meshblu-core-manager-subscription'

class EnqueueJobsForSubscriptionsMessageReceived
  constructor: ({datastore,@jobManager,uuidAliasResolver}) ->
    @subscriptionManager ?= new SubscriptionManager {datastore, uuidAliasResolver}

  _doCallback: (request, code, callback) =>
    response =
      metadata:
        responseId: request.metadata.responseId
        code: code
        status: http.STATUS_CODES[code]
    callback null, response

  do: (request, callback) =>
    {fromUuid, toUuid, messageRoute} = request.metadata
    if _.some(messageRoute, {toUuid: toUuid, fromUuid: fromUuid, type: 'message.received'})
      return @_doCallback request, 204, callback

    @subscriptionManager.emitterListForType {emitterUuid: toUuid, type: 'message.received'}, (error, subscriptions) =>
      return callback error if error?
      return @_doCallback request, 204, callback if _.isEmpty subscriptions

      requests = _.map subscriptions, (subscription) =>
        @_buildRequest {request, subscription}

      async.each requests, @_createRequest, (error) =>
        return callback error if error?
        return @_doCallback request, 204, callback

  _buildRequest: ({request, subscription}) =>
    hop  =
      fromUuid: request.metadata.fromUuid
      toUuid: request.metadata.toUuid
      type: 'message.received'

    messageRoute = _.compact [hop].concat request.metadata.messageRoute

    return {
      metadata:
        jobType: 'DeliverSubscriptionMessageReceived'
        auth:
          uuid: subscription.subscriberUuid
        fromUuid: subscription.emitterUuid
        toUuid: subscription.subscriberUuid
        messageRoute: messageRoute
      rawData: request.rawData
    }

  _createRequest: (request, callback) =>
    @jobManager.createRequest 'request', request, callback

module.exports = EnqueueJobsForSubscriptionsMessageReceived
