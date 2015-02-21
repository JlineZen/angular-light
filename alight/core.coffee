# Angular light
# version: 0.7.15 / 2015-02-05

# init
alight.version = '0.7.15'
alight.debug =
    optimize: false
    scan: false
    directive: false
    watch: false
    watchText: false
    parser: false
alight.scopes = []
alight.controllers = {}
alight.filters = {}
alight.utilits = {}
alight.directives =
    al: {}
    bo: {}
    ctrl: {}
alight.text = {}
alight.apps = {}


alight.directivePreprocessor = directivePreprocessor = (ns, name, args) ->
    name = name.replace /(-\w)/g, (m) ->
        m.substring(1).toUpperCase()

    if args.scope.$ns
        raw = args.scope.$ns.directives[ns][name]
    else        
        raw = alight.directives[ns][name]
    if not raw
        return { noDirective: true }

    dir = {}
    if f$.isFunction raw
        dir.init = raw
    else if f$.isObject raw
        for k, v of raw
            dir[k] = v
    else throw 'Wrong directive: ' + ns + '.' + name
    dir.priority = raw.priority or 0
    dir.restrict = raw.restrict or 'A'

    if dir.restrict.indexOf(args.attr_type) < 0
        throw 'Directive has wrong binding (attribute/element): ' + name

    dir.$init = (element, expression, scope, env) ->

        doProcess = ->
            l = dscope.procLine
            for dp, i in l
                dp.fn.call dscope
                if dscope.isDeferred
                    dscope.procLine = l[i+1..]
                    break
            null

        dscope =
            element: element
            expression: expression
            scope: scope
            env: env
            ns: ns
            name: name
            args: args
            directive: dir
            result: {}
            
            isDeferred: false
            procLine: directivePreprocessor.ext
            makeDeferred: ->
                dscope.isDeferred = true
                dscope.result.owner = true
                dscope.directive.scope = true

                ->
                    dscope.isDeferred = false
                    doProcess()

        doProcess()        
        dscope.result
    dir


do ->
    directivePreprocessor.ext = ext = []

    ext.push
        code: 'init'
        fn: ->
            if @.directive.init
                @.result = @.directive.init(@.element, @.expression, @.scope, @.env) or {}
            if not f$.isObject(@.result)
                @.result = {}

    ext.push
        code: 'templateUrl'
        fn: ->
            ds = @
            if @.directive.templateUrl
                callback = @.makeDeferred()
                f$.ajax
                    cache: true
                    url: @.directive.templateUrl
                    success: (html) ->
                        ds.directive.template = html
                        callback()
                    error: callback

    ext.push
        code: 'template'
        fn: ->
            if @.directive.template
                if @.element.nodeType is 1
                    f$.html @.element, @.directive.template
                else if @.element.nodeType is 8
                    el = document.createElement 'p'
                    el.innerHTML = @.directive.template.trimLeft()
                    el = el.firstChild
                    f$.after @.element, el
                    @.element = el
                    if not @.directive.scope
                        @.directive.scope = true

    ext.push
        code: 'scope'
        fn: ->
            if @.directive.scope
                parentScope = @.scope
                @.scope = parentScope.$new(@.directive.scope is 'isolate')
                @.result.owner = true
                @.doBinding = true

    ext.push
        code: 'link'
        fn: ->
            if @.directive.link
                @.directive.link(@.element, @.expression, @.scope, @.env)

    ext.push
        code: 'scopeBinding'
        fn: (element, expression, scope, env) ->
            if @.doBinding
                alight.applyBindings @.scope, @.element, { skip_attr:@.env.skippedAttr() }


testDirective = do ->
    addAttr = (attrName, args, base) ->
        if args.attr_type is 'A'
            attr = base or {}
            attr.priority = -5
            attr.is_attr = true
            attr.name = attrName
            attr.attrName = attrName
            attr.element = args.element
            args.list.push attr

    (attrName, args) ->
        if args.skip_attr.indexOf(attrName) >= 0
            return addAttr attrName, args, { skip:true }

        j = attrName.indexOf '-'
        if j < 0
            return addAttr attrName, args
        ns = attrName.substring 0, j
        name = attrName.substring j+1
        scope = args.scope
        if scope.$ns
            path = (scope.$ns.directives or {})[ns]
        else
            path = alight.directives[ns]
        if not path
            return addAttr attrName, args

        directive = alight.directivePreprocessor ns, name, args
        if directive.noDirective
            return addAttr attrName, args, { noDirective:true }

        args.list.push
            name: name
            directive: directive
            priority: directive.priority
            attrName: attrName


sortByPriority = (a, b) ->
    if a.priority == b.priority
        return 0
    if a.priority > b.priority
        return -1
    else
        return 1


attrBinding = (element, value, scope, attrName) ->
    text = value
    if text.indexOf(alight.utilits.pars_start_tag) < 0
        return

    setter = (result) ->
        f$.attr element, attrName, result
    w = scope.$watchText text, setter,
        readOnly: true
    setter w.value


textBinding = (scope, node) ->
    text = node.data
    if text.indexOf(alight.utilits.pars_start_tag) < 0
        return
    setter = (result) ->
        node.nodeValue = result
    w = scope.$watchText text, setter,
        readOnly: true
    setter w.value


bindComment = (scope, element) ->
    text = element.nodeValue.trimLeft()
    if text[0..9] isnt 'directive:'
        return
    text = text[10..].trimLeft()
    i = text.indexOf ' '
    if i >= 0
        dirName = text[0..i-1]
        value = text[i+1..]
    else
        dirName = text
        value = ''

    args =
        list: list = []
        element: element
        attr_type: 'M'
        scope: scope
        skip_attr: []
    
    testDirective dirName, args

    d = list[0]
    if d.noDirective
        throw "Directive not found: #{d.name}"

    directive = d.directive
    env =
        element: element
        attrName: dirName
        attributes: []
        skippedAttr: ->
            []
    if alight.debug.directive
        console.log 'bind', d.attrName, value, d
    try
        result = directive.$init element, value, scope, env
        if result and result.start
            result.start()
    catch e
        alight.exceptionHandler e, 'Error in directive: ' + d.name,
            value: value
            env: env
            scope: scope
            element: element


process = do ->
    takeAttr = (name, skip) ->
        if arguments.length is 1
            skip = true
        for attr in @.attributes
            if attr.attrName isnt name
                continue
            if skip
                attr.skip = true
            value = f$.attr @.element, name
            return value or true

    skippedAttr = ->
        for attr in @.attributes
            if not attr.skip
                continue
            attr.attrName

    (scope, element, config) ->
        config = config || {}
        skip_children = false
        skip_attr = config.skip_attr or []
        if not (skip_attr instanceof Array)
            skip_attr = [skip_attr]

        if !config.skip_top
            args =
                list: list = []
                element: element
                skip_attr: skip_attr
                attr_type: 'E'
                scope: scope
            
            attrName = element.nodeName.toLowerCase()
            testDirective attrName, args

            args.attr_type = 'A'
            attrs = f$.getAttributes element
            for attrName, attr_value of attrs
                testDirective attrName, args

            # sort by priority
            list = list.sort sortByPriority

            for d in list
                if d.skip
                    continue
                if d.noDirective
                    throw "Directive not found: #{d.name}"
                d.skip = true
                value = f$.attr element, d.attrName
                if d.is_attr
                    attrBinding element, value, scope, d.attrName
                else
                    directive = d.directive
                    env =
                        element: element
                        attrName: d.attrName
                        attributes: list
                        takeAttr: takeAttr
                        skippedAttr: skippedAttr
                    if alight.debug.directive
                        console.log 'bind', d.attrName, value, d
                    try
                        result = directive.$init element, value, scope, env
                        if result and result.start
                            result.start()
                    catch e
                        alight.exceptionHandler e, 'Error in directive: ' + d.attrName,
                            value: value
                            env: env
                            scope: scope
                            element: element

                    if result and result.owner
                        skip_children = true
                        break

        if !skip_children
            # text bindings
            for node in f$.childNodes element
                if not node
                    continue
                fn = nodeTypeBind[node.nodeType]
                if fn
                    fn scope, node
        null

nodeTypeBind =
    1: process      # element
    3: textBinding  # text
    8: bindComment  # comment


Scope = () ->
    `if(!(this instanceof Scope)) return new Scope()`
    this.$system =
        watches: {}
        watchList: []
        watch_any: []
        root: this
        children: []
        scan_callbacks: []
        destroy_callbacks: []
        finishBinding_callbacks: []
        finishBinding_lock: false
    this

alight.Scope = Scope


Scope::$new = (isolate) ->
    scope = this

    if isolate
        child = alight.Scope()
    else
        if not scope.$system.ChildScope
            scope.$system.ChildScope = ->
                @.$system =
                    watches: {}
                    watchList: []
                    watch_any: []
                    root: scope.$system.root
                    children: []
                    destroy_callbacks: []
                @

            scope.$system.ChildScope:: = scope
        child = new scope.$system.ChildScope()

    child.$parent = scope
    scope.$system.children.push child
    child


###
$watch
    name:
        expression or function
        $any
        $destroy
        $finishBinding
    callback:
        function
    option:
        isArray (is_array)
        readOnly
        init
        deep

###
Scope::$watch = (name, callback, option) ->
    scope = @
    if option is true
        option =
            isArray: true
    else if not option
        option = {}
    if option.is_array  # compatibility with old version
        option.isArray = true
    if f$.isFunction name
        exp = name
        key = alight.utilits.getId()
    else
        exp = null
        name = name.trim()
        if name[0..1] is '::'
            name = name[2..]
            option.oneTime = true
        key = name
        if key is '$any'
            return scope.$system.watch_any.push callback
        if key is '$destroy'
            return scope.$system.destroy_callbacks.push callback
        if key is '$finishBinding'
            return scope.$system.root.$system.finishBinding_callbacks.push callback
        if option.deep
            key = 'd#' + key
        else if option.isArray
            key = 'a#' + key
        else
            key = 'v#' + key

    if alight.debug.watch
        console.log '$watch', name

    d = scope.$system.watches[key]
    if d
        if not option.readOnly
            d.extraLoop = true
    else
        # create watch object
        exp = exp or scope.$compile name,
            noBind: true
        value = exp scope
        if option.deep
            value = alight.utilits.clone value
            option.isArray = false
        else if option.isArray and f$.isArray value
                value = value.slice()
        scope.$system.watches[key] = d =
            isArray: Boolean option.isArray
            extraLoop: not option.readOnly
            deep: option.deep
            value: value
            callbacks: []
            exp: exp
            src: '' + name
        scope.$system.watchList.push d

    r =
        $: d
        value: d.value

    if option.oneTime
        realCallback = callback
        callback = (value) ->
            if value is undefined
                return
            r.stop()
            realCallback value

    d.callbacks.push callback
    r.stop = ->
        i = d.callbacks.indexOf callback
        if i >= 0
            d.callbacks.splice i, 1
            if d.callbacks.length isnt 0
                return
            # remove watch
            delete scope.$system.watches[key]
            i = scope.$system.watchList.indexOf d
            if i >= 0
                scope.$system.watchList.splice i, 1

    if option.init
        callback r.value

    r


###
    cfg:
        no_return   - method without return (exec)
        string      - method will return result as string
        stringOrOneTime
        input   - list of input arguments
        full    - full response
        noBind  - get function without bind to scope
        rawExpression

###

do ->
    compile_cache = {}
    filtered = {}

    Scope::$compile = (src_exp, cfg) ->
        cfg = cfg or {}
        scope = @
        # make hash
        resp = {}
        src_exp = src_exp.trim()
        if src_exp[0..1] is '::'
            src_exp = src_exp[2..]
            resp.oneTime = true

        if cfg.stringOrOneTime
            cfg.string = not resp.oneTime

        hash = src_exp + '#'
        hash += if cfg.no_return then '+' else '-'
        hash += if cfg.string then 's' else 'v'
        if cfg.input
            hash += cfg.input.join ','

        func = compile_cache[hash]
        if not func
            exp = src_exp

            no_return = cfg.no_return or false
            ff = alight.utilits.parsExpression exp,
                input: cfg.input
            exp = ff[0]
            filters = ff.slice(1)
            if no_return
                result = "var $$;#{exp}"
            else
                if cfg.string and not filters.length
                    result = "var $$, __ = (#{exp}); return '' + (__ || (__ == null?'':__))"
                    if cfg.rawExpression
                        resp.rawExpression = "(__=#{exp}) || (__ == null?'':__)"
                else
                    result = "var $$;return (#{exp})"
            try
                if cfg.input
                    args = cfg.input.slice()
                    args.unshift '$$scope'
                    args.push result
                    func = Function.apply null, args
                else
                    func = Function '$$scope', result
            catch e
                alight.exceptionHandler e, 'Wrong expression: ' + src_exp,
                    src: src_exp
                    cfg: cfg
                throw 'Wrong expression: ' + exp

            compile_cache[hash] = func
            if filters.length
                filtered[hash] = filters
        else
            filters = filtered[hash] or null

        if filters and filters.length
            func = alight.utilits.filterBuilder scope, func, filters
            if cfg.string
                f1 = func
                `func = function() { var __ = f1.apply(this, arguments); return '' + (__ || (__ == null?'':__)) }`

        if cfg.noBind
            resp.fn = func
        else
            if (cfg.input || []).length < 4
                resp.fn = ->
                    try
                        func scope, arguments[0], arguments[1], arguments[2]
                    catch e
                        alight.exceptionHandler e, 'Wrong in expression: ' + src_exp,
                            src: src_exp
                            cfg: cfg
            else
                resp.fn = ->
                    try
                        a = [scope]
                        for i in arguments
                            a.push i
                        func.apply null, a
                    catch e
                        alight.exceptionHandler e, 'Wrong in expression: ' + src_exp,
                            src: src_exp
                            cfg: cfg

        if cfg.full
            return resp
        resp.fn


Scope::$eval = (exp) ->
    @.$compile(exp, {noBind: true})(@)


Scope::$getValue = (name) ->
    dict = @
    for key in name.split '.'
        dict = (dict or {})[key]
    dict


Scope::$setValue = (name, value) ->
    dict = @
    d = name.split '.'
    for i in [0..d.length-2] by 1
        key = d[i]
        child = dict[key]
        if child is undefined
            dict[key] = child = {}
        dict = child
    key = d[d.length-1]
    dict[key] = value


Scope::$destroy = () ->
    scope = this

    # fire callbacks
    for cb in scope.$system.destroy_callbacks
        cb scope
    scope.$system.destroy_callbacks = []

    # remove children
    for it in scope.$system.children.slice()
        it.$destroy()

    # remove from parent
    if scope.$parent
        i = scope.$parent.$system.children.indexOf scope
        scope.$parent.$system.children.splice i, 1

    # remove watch
    scope.$parent = null
    scope.$system.watches = {}
    scope.$system.watchList = []
    scope.$system.watch_any.length = 0


get_time = do ->
    if window.performance
        return ->
            Math.floor performance.now()
    ->
        (new Date()).getTime()


notEqual = (a, b) ->
    if a is null or b is null
        return true
    ta = typeof a
    tb = typeof b
    if ta isnt tb
        return true
    if ta is 'object'
        if a.length isnt b.length
            return true
        for v, i in a
            if v isnt b[i]
                return true
    false

`
  var scan_core_opt = function(top, result) {
    var anyList, callback, changes, extraLoop, index, last, line, mutated, queue, scope, sys, total, value, w, _i, _j, _len, _len1, _ref, _ref1;
    extraLoop = false;
    changes = 0;
    total = 0;
    anyList = [];
    line = [];
    queue = [top];
    while (queue) {
      scope = queue[0];
      index = 1;
      while (scope) {
        sys = scope.$system;
        total += sys.watchList.length;
        _ref = sys.watchList;
        for (_len = _ref.length;_len;) {
          _len--;
          w = _ref[_len];
          last = w.value;
          value = w.exp(scope);
          if (last !== value) {
            mutated = false;
            if (w.isArray) {
              if (notEqual(last, value)) {
                if (f$.isArray(value)) {
                  w.value = value.slice();
                } else {
                  w.value = value;
                }
                mutated = true;
              }
            } else if (w.deep) {
              if (!alight.utilits.equal(last, value)) {
                mutated = true;
                w.value = alight.utilits.clone(value);
              }
            } else {
              mutated = true;
              w.value = value;
            }
            if (mutated) {
              mutated = false;
              changes++;
              if (w.extraLoop) {
                extraLoop = true;
              }
              _ref1 = w.callbacks.slice();
              for (_j = 0, _len1 = _ref1.length; _j < _len1; _j++) {
                callback = _ref1[_j];
                callback.call(scope, value);
              }
            }
          }
        }
        if (sys.children.length) {
          line.push(sys.children);
        }
        if (sys.watch_any.length) {
          anyList.push.apply(anyList, sys.watch_any);
        }
        scope = queue[index++];
      }
      queue = line.shift();
    }
    result.total = total;
    result.changes = changes;
    result.extraLoop = extraLoop;
    result.anyList = anyList;
  };
`

scan_core = (top, result) ->
    extraLoop = false
    changes = 0
    total = 0
    anyList = []
    line = []
    queue = [top]
    while queue
        scope = queue[0]
        index = 1
        while scope
            sys = scope.$system
            total += sys.watchList.length
            for w in sys.watchList
                result.src = w.src
                last = w.value
                value = w.exp scope
                if last isnt value
                    mutated = false
                    if w.isArray
                        if notEqual last, value
                            if f$.isArray value
                                w.value = value.slice()
                            else
                                w.value = value
                            mutated = true
                    else if w.deep
                        if not alight.utilits.equal last, value
                            mutated = true
                            w.value = alight.utilits.clone value
                    else
                        mutated = true
                        w.value = value

                    if mutated
                        mutated = false
                        changes++
                        if w.extraLoop
                            extraLoop = true
                        for callback in w.callbacks.slice()
                            callback.call scope, value
                    if alight.debug.scan
                        console.log 'changed:', w.src

            if sys.children.length
                line.push sys.children
            # add callbacks to $any
            if sys.watch_any.length
                anyList.push.apply anyList, sys.watch_any
            scope = queue[index++]
        
        queue = line.shift()

    result.total = total
    result.changes = changes
    result.extraLoop = extraLoop
    result.anyList = anyList


Scope::$scan = (cfg) ->
    cfg = cfg or {}
    if f$.isFunction cfg
        cfg =
            callback: cfg
    root = this.$system.root
    top = cfg.top or root
    if cfg.callback
        root.$system.scan_callbacks.push cfg.callback
    if root.$system.status is 'scaning'
        root.$system.extraLoop = true
        return
    if cfg.late
        if top isnt root
            throw 'conflict: late and top'
        if root.$system.lateScan
            return
        root.$system.lateScan = true
        alight.nextTick ->
            if root.$system.lateScan
                root.$scan()
        return
    root.$system.lateScan = false
    root.$system.status = 'scaning'

    if alight.debug.scan
        start = get_time()

    mainLoop = 10
    try
        while mainLoop
            mainLoop--

            root.$system.extraLoop = false

            result = {}
            if alight.debug.optimize
                scan_core_opt top, result
            else
                scan_core top, result

            # call $any
            if result.changes
                for cb in result.anyList
                    cb()
            if not result.extraLoop and not root.$system.extraLoop
                break
        if alight.debug.scan
            duration = get_time() - start
            console.log "$scan: (#{10-mainLoop}) #{result.total} / #{duration}ms"
    catch e
        alight.exceptionHandler e, '$scan, error in expression: ' + result.src,
            src: result.src
            result: result
    finally
        root.$system.status = null
        scb = root.$system.scan_callbacks.slice()
        root.$system.scan_callbacks.length = 0
        for callback in scb
            callback.call root

    if mainLoop is 0
        throw 'Infinity loop detected'


###
    $compileText = (text, cfg)
    cfg:
        result_on_static
        onStatic
###
do ->
    ctCache = {}
    simpleCache = {}

    isStatic = (data) ->
        for i in data
            if i.type is 'expression' and not i.static
                return false
        true

    Scope::$compileText = (text, cfg) ->
        scope = @
        cfg = cfg or {}

        fn = simpleCache[text]
        if fn
            return fn

        if text.indexOf(alight.utilits.pars_start_tag) < 0
            if cfg.result_on_static
                return text
            return ->
                text

        data = alight.utilits.parsText text
        data.scope = scope

        compile = ->
            fn = ctCache[text]
            if fn
                return ->
                    fn.call data

            result = []
            for d, index in data
                if d.type is 'expression'
                    if d.fn
                        result.push "this[#{index}].fn(this.scope)"
                    else
                        # text directive
                        result.push "((x=this[#{index}].value) || (x == null?'':x))"
                else if d.value
                    `result.push('"' + d.value.replace(/\\/g,'\\\\').replace(/"/g,'\\"').replace(/\n/g,'\\n') + '"')`
            result = result.join ' + '
            fn = new Function "var x; return (#{result})"
            ctCache[text] = fn
            ->
                fn.call data

        simpleCompile = ->
            result = []
            for d, index in data
                if d.type is 'expression'
                    result.push "(#{d.re})"                    
                else if d.value
                    `result.push('"' + d.value.replace(/\\/g,'\\\\').replace(/"/g,'\\"').replace(/\n/g,'\\n') + '"')`
            result = result.join ' + '
            fn = new Function '$$scope', "var $$, __; return (#{result})"
            simpleCache[text] = fn
            fn

        # data: type, value, fn, list, static
        watch_count = 0
        simple = true
        for d in data
            if d.type is 'expression'

                if d.list[0][0] is '='  # bind once
                    d.list[0] = '#bindonce ' + d.list[0].slice 1

                exp = d.list.join ' | '

                if exp[0] is '#'
                    simple = false
                    do (d=d) ->

                        async = false
                        env =
                            data: d
                            setter: (value) ->
                                d.value = value
                            finally: (value) ->
                                if arguments.length is 1
                                    env.setter value
                                d.static = true
                                if async and cfg.onStatic and isStatic(data)
                                    cfg.onStatic()
                        alight.text.$base scope, d, env
                        async = true
                    if not d.static
                        watch_count++
                else
                    ce = scope.$compile exp,
                        stringOrOneTime: true
                        full: true
                        rawExpression: true
                        noBind: true
                    if ce.oneTime
                        simple = false
                        do (d=d, ce=ce) ->
                            d.fn = ->
                                v = ce.fn scope
                                if v is undefined
                                    return ''
                                if v is null
                                    v = ''
                                d.fn = ->
                                    v
                                d.static = true
                                if cfg.onStatic and isStatic(data)
                                    cfg.onStatic()
                                v
                    else
                        d.fn = ce.fn
                        if ce.rawExpression
                            d.re = ce.rawExpression
                        else
                            simple = false
                    watch_count++
        if watch_count
            if simple
                return simpleCompile()
            else
                return compile()
        else
            value = compile()()
            if cfg.result_on_static
                return value
            else
                ->
                    value


Scope::$evalText = (exp) ->
    @.$compileText(exp)(@)


###
    Scope.$watchText(name, callback, config)
    config.readOnly
    config.onStatic
###
Scope::$watchText = (name, callback, config) ->
    scope = @
    config = config or {}

    if alight.debug.watchText
        console.log '$watchText', name

    w = scope.$system.watches;
    d = w[name]
    if d
        if not config.readOnly
            d.extraLoop = true
    else
        # create watch object
        d =
            extraLoop: not config.readOnly
            isArray: false
            callbacks: []
            onStatic: []
            src: name

        exp = scope.$compileText name,
            result_on_static: true
            onStatic: ->
                value = exp.call scope

                clean = ->
                    d.exp = ->
                        value
                    scope.$scan ->
                        # remove watch
                        d.callbacks.length = 0
                        delete w[name]
                        i = scope.$system.watchList.indexOf d
                        if i >= 0
                            scope.$system.watchList.splice i, 1


                # remove watch
                if scope.$system.root.$system.status is 'scaning'
                    clean()
                else
                    d.exp = ->
                        if scope.$system.root.$system.status isnt 'scaning'
                            throw 'Error, no scanning'
                        clean()
                        value

                # call listeners
                for cb in d.onStatic
                    cb value
                null
        if not f$.isFunction exp  # no watch
            return { value: exp }
        d.exp = exp
        d.value = exp scope
        w[name] = d
        scope.$system.watchList.push d

    if config.onStatic
        d.onStatic.push config.onStatic

    d.callbacks.push callback

    r =
        $: d
        value: d.value
        exp: d.exp
        stop: ->
            i = d.callbacks.indexOf callback
            if i >= 0
                d.callbacks.splice i, 1
                if d.callbacks.length isnt 0
                    return
                # remove watch
                delete w[name]
                i = scope.$system.watchList.indexOf d
                if i >= 0
                    scope.$system.watchList.splice i, 1

    r


alight.nextTick = do ->
    timer = null
    list = []
    exec = ->
        timer = null
        dlist = list.slice()
        list.length = 0
        for it in dlist
            callback = it[0]
            self = it[1]
            try
                callback.call self
            catch e
                alight.exceptionHandler e, '$nextTick, error in function',
                    fn: callback
        null

    (callback) ->
        list.push [callback, @]
        if timer
            return
        timer = setTimeout exec, 0


alight.getController = (name, scope) ->
    if scope.$ns
        ctrl = (scope.$ns.controllers or {})[name]
    else
        ctrl = alight.controllers[name] or (enableGlobalControllers and window[name])
    if not ctrl
        throw 'Controller isn\'t found: ' + name
    if not (ctrl instanceof Function)
        throw 'Wrong controller: ' + name
    ctrl


alight.getFilter = (name, scope, param) ->
    if scope.$ns
        filter = (scope.$ns.filters or {})[name]
    else
        filter = alight.filters[name]
    if not filter
        throw 'Filter not found: ' + name
    filter


alight.text.$base = (scope, data, env) ->
    exp = data.list[0]
    i = exp.indexOf ' '
    if i < 0
        dir_name = exp.slice 1
        exp = ''
    else
        dir_name = exp.slice 1, i
        exp = exp.slice i

    dir = alight.text[dir_name]
    if not dir
        throw 'No directive alight.text.' + dir_name

    if data.list.length > 1  # filters
        filter = alight.utilits.filterBuilder scope, null, data.list.slice(1)
        env.setter = (result) ->
            data.value = filter result

    dir env.setter, exp, scope, env


alight.applyBindings = (scope, element, config) ->
    if not element
        throw 'No element'

    if not scope
        scope = new alight.Scope()

    finishBinding = not scope.$system.root.$system.finishBinding_lock
    if finishBinding
        scope.$system.root.$system.finishBinding_lock = true

    config = config or {}

    process scope, element, config
    
    if finishBinding
        scope.$system.root.$system.finishBinding_lock = false
        lst = scope.$system.root.$system.finishBinding_callbacks.slice()
        scope.$system.root.$system.finishBinding_callbacks.length = 0
        for cb in lst
            cb()
    null


alight.bootstrap = (elements) ->
    if not elements
        elements = f$.find document, '[al-app]'
    if not (f$.isArray(elements) or elements.length isnt undefined)
        elements = [elements]
    for element in elements
        if element.ma_bootstrapped
            continue
        element.ma_bootstrapped = true
        attr = f$.attr element, 'al-app'
        if attr
            if attr[0] is '#'
                t = attr.split ' '
                tag = t[0].substring(1)
                ctrlName = t[1]
                scope = alight.apps[tag]
                if scope
                    if ctrlName
                        console.error "New controller on exists scope: al-app=\"#{attr}\""
                else
                    alight.apps[tag] = scope = alight.Scope()
                    if ctrlName
                        ctrl = alight.getController ctrlName, scope
                        ctrl scope
            else
                scope = alight.Scope()
                ctrl = alight.getController attr, scope
                ctrl scope
        else
            scope = alight.Scope()
        alight.applyBindings scope, element, { skip_attr: 'al-app' }
    null