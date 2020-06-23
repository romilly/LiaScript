import {
  lia
} from './logger'

window.event_semaphore = 0
var lia_queue = []

// Basic class for handline Code-Errors
class LiaError extends Error {
  constructor (message, files, ...params) {
    super(...params)
    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, LiaError)
    }

    this.message = message
    this.details = []

    for (let i = 0; i < files; i++) {
      this.details.push([])
    }
  }

  add_detail (fileId, msg, type, line, column) {
    this.details[fileId].push({
      row: line,
      column: column,
      text: msg,
      type: type
    })
  }

  get_detail (msg, type, line, column = 0) {
    return {
      row: line,
      column: column,
      text: msg,
      type: type
    }
  }

  // sometimes you need to adjust the compile messages to fit into the
  // editor ... use this function to adapt the row parameters ...
  // file_id with 0 will apply the correction value to all files
  correct_lines (fileId, by) {
    if (fileId == null) {
      for (let i = 0; i < this.details.length; i++) {
        this.correct_lines(i, by)
      }
    } else {
      this.details[fileId] = this.details[fileId].map((e) => {
        e.line = e.line + by
      })
    }
  }
};



class LiaEvents {
  constructor () {
    this.event = {}
    this.input = {}
  }

  register (name, fn) {
    this.event[name] = fn
  }

  register_input (id1, id2, name, fn) {
    if (this.input[id1] === undefined) {
      this.input[id1] = {}
    }
    if (this.input[id1][id2] === undefined) {
      this.input[id1][id2] = {}
    }

    this.input[id1][id2][name] = fn
  }

  dispatch_input (event) { // id1, id2, name, msg) {
    try {
      this.input[event.section][event.message.section][event.message.topic](event.message.message);
    } catch (e) {
      lia.error('unable to dispatch message', event.message)
    }
  }

  dispatch (name, data) {
    if (this.event.hasOwnProperty(name)) {
      this.event[name](data)
    }
  }

  remove (name) {
    delete this.event[name]
  }
};

function getLineNumber (error) {
  try {
    // firefox
    const firefoxRegex = /<anonymous>:(\d+):\d+/
    if (error.stack.match(firefoxRegex)) {
      const res = error.stack.match(firefoxRegex)
      return parseInt(res[1], 10)
    }

    // chrome
    const chromeRegex = /<anonymous>.+:(\d+):\d+/
    if (error.stack.match(chromeRegex)) {
      const res = error.stack.match(chromeRegex)
      return parseInt(res[1], 10)
    }
  } catch (e) {

  }
};

function lia_wait () {
  if (window.event_semaphore > 0) {
    setTimeout(function(e) { lia_wait() }, 100)
  } else {
    while(lia_queue.length) {
      let event = lia_queue.pop()

      if (event.type == "eval")
        lia_eval (event.code, event.send)
      else if (event.type == "exec")
        lia_execute_event (event.event)
      else
        lia.warn("lia_queue => unknown event => ", JSON.stringify(event))
    }
  }
}

function lia_eval (code, send) {
  if (window.event_semaphore > 0) {
    lia_queue.push({type: "eval", code: code, send: send})

    if (lia_queue.length == 1) {
      lia_wait()
    }
    return
  }

  try {
    let console = {
      debug: (...args) => send.log('debug', '\n', args),
      log: (...args) => send.log('info', '\n', args),
      warn: (...args) => send.log('warn', '\n', args),
      error: (...args) => send.log('error', '\n', args),
      clear: () => send.lia('LIA: clear')
    }

    console.clear()

    send.lia(String(eval(code + '\n', send, console)))
  } catch (e) {
    if (e instanceof LiaError) {
      send.lia(e.message, e.details, false)
    } else {
      send.lia(e.message, [], false)
    }
  }
};

function lia_eval_event (send, handler, event) {
  lia_eval(
    event.message.message, {
      lia: (result, details = [], ok = true) => {
        event.message.topic = 'eval'
        event.message.message = {
          result: result,
          details: details,
          ok: ok
        }
        send(event)
      },
      log: (topic, sep, ...args) => {
        event.message.topic = topic
        event.message.message = list_to_string(sep, args)
        send(event)
      },
      //service: websocket(channel),
      handle: (name, fn) => {
        let e1 = event.section
        let e2 = event.message.section
        handler.register_input(e1, e2, name, fn)
      },
      register: (name, fn) => {
        handler.register(name, fn)
      },
      dispatch: (name, data) => {
        handler.dispatch(name, data)
      }
    }
  )
};

function list_to_string (sep, list) {
  let str = ''

  for (let i = 0; i < list[0].length; i++) {
    str += list[0][i].toString() + ' '
  }

  return str + sep
};

function lia_execute_event (event) {
  if (window.event_semaphore > 0) {
    lia_queue.push({type: "exec", event: event})

    if (lia_queue.length == 1) {
      lia_wait()
    }
    return
  }

  try {
    setTimeout(() => {
      eval(event.code)
    }, event.delay)
  } catch (e) {
    lia.error('exec => ', e)
  }
};

function websocket (channel = null) {
  if (channel) {
    return function (eventID, message) {
      return channel.push('lia', {
        event_id: eventID,
        message: message
      })
    }
  }
};

export {
  LiaEvents,
  lia_execute_event,
  lia_eval_event
}
