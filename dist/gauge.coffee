# Request Animation Frame Polyfill
# CoffeeScript version of http://paulirish.com/2011/requestanimationframe-for-smart-animating/
do () ->
	vendors = ['ms', 'moz', 'webkit', 'o']
	for vendor in vendors
		if window.requestAnimationFrame
			break
		window.requestAnimationFrame = window[vendor + 'RequestAnimationFrame']
		window.cancelAnimationFrame = window[vendor + 'CancelAnimationFrame'] or window[vendor + 'CancelRequestAnimationFrame']

	browserRequestAnimationFrame = null
	lastId = 0
	isCancelled = {}

	if not requestAnimationFrame
		window.requestAnimationFrame = (callback, element) ->
			currTime = new Date().getTime()
			timeToCall = Math.max(0, 16 - (currTime - lastTime))
			id = window.setTimeout(() ->
				callback(currTime + timeToCall)
			, timeToCall)
			lastTime = currTime + timeToCall
			return id
		# This implementation should only be used with the setTimeout()
		# version of window.requestAnimationFrame().
		window.cancelAnimationFrame = (id) ->
			clearTimeout(id)
	else if not window.cancelAnimationFrame
		browserRequestAnimationFrame = window.requestAnimationFrame
		window.requestAnimationFrame = (callback, element) ->
			myId = ++lastId
			browserRequestAnimationFrame(() ->
				if not isCancelled[myId]
					callback()
			, element)
			return myId
		window.cancelAnimationFrame = (id) ->
			isCancelled[id] = true

String.prototype.hashCode = () ->
	hash = 0
	if this.length == 0
		return hash
	for i in [0...this.length]
		char = this.charCodeAt(i)
		hash = ((hash << 5) - hash) + char
		hash = hash & hash # Convert to 32bit integer
	return hash

secondsToString = (sec) ->
	hr = Math.floor(sec / 3600)
	min = Math.floor((sec - (hr * 3600))/60)
	sec -= ((hr * 3600) + (min * 60))
	sec += ''
	min += ''
	while min.length < 2
		min = '0' + min
	while sec.length < 2
		sec = '0' + sec
	hr = if hr then hr + ':' else ''
	return hr + min + ':' + sec

formatNumber = (num...) ->
	value = num[0]
	digits = 0 || num[1]
	return addCommas(value.toFixed(digits))

updateObjectValues = (obj1, obj2) ->
	for own key, val of obj2
		obj1[key] = val
	return obj1

mergeObjects = (obj1, obj2) ->
	out = {}
	for own key, val of obj1
		out[key] = val
	for own key, val of obj2
		out[key] = val
	return out

addCommas = (nStr) ->
	nStr += ''
	x = nStr.split('.')
	x1 = x[0]
	x2 = ''
	if x.length > 1
		x2 = '.' + x[1]
	rgx = /(\d+)(\d{3})/
	while rgx.test(x1)
		x1 = x1.replace(rgx, '$1' + ',' + '$2')
	return x1 + x2

cutHex = (nStr) ->
	if nStr.charAt(0) == "#"
		return nStr.substring(1,7)
	return nStr

class ValueUpdater
	animationSpeed: 32
	constructor: (addToAnimationQueue=true, @clear=true) ->
		if addToAnimationQueue
			AnimationUpdater.add(@)

	update: (force=false) ->
		if force or @displayedValue != @value
			if @ctx and @clear
				@ctx.clearRect(0, 0, @canvas.width, @canvas.height)
			diff = @value - @displayedValue
			if Math.abs(diff / @animationSpeed) <= 0.001
				@displayedValue = @value
			else
				@displayedValue = @displayedValue + diff / @animationSpeed
			@render()
			return true
		return false

class BaseGauge extends ValueUpdater
	displayScale: 1

	setTextField: (textField, fractionDigits) ->
		@textField = if textField instanceof TextRenderer then textField else new TextRenderer(textField, fractionDigits)

	setMinValue: (@minValue, updateStartValue=true) ->
		if updateStartValue
			@displayedValue = @minValue
			for gauge in @gp or []
				gauge.displayedValue = @minValue

	setOptions: (options=null) ->
		@options = mergeObjects(@options, options)
		if @textField
			@textField.el.style.fontSize = options.fontSize + 'px'

		if @options.angle > .5
			@options.angle = .5
		@configDisplayScale()
		return @

	configDisplayScale: () ->
		prevDisplayScale = @displayScale

		if @options.highDpiSupport == false
			delete @displayScale
		else
			devicePixelRatio = window.devicePixelRatio or 1
			backingStorePixelRatio =
				@ctx.webkitBackingStorePixelRatio or
				@ctx.mozBackingStorePixelRatio or
				@ctx.msBackingStorePixelRatio or
				@ctx.oBackingStorePixelRatio or
				@ctx.backingStorePixelRatio or 1
			@displayScale = devicePixelRatio / backingStorePixelRatio

		if @displayScale != prevDisplayScale
			width = @canvas.G__width or @canvas.width
			height = @canvas.G__height or @canvas.height
			@canvas.width = width * @displayScale
			@canvas.height = height * @displayScale
			@canvas.style.width = "#{width}px"
			@canvas.style.height = "#{height}px"
			@canvas.G__width = width
			@canvas.G__height = height

		return @

class TextRenderer
	constructor: (@el, @fractionDigits) ->

	# Default behaviour, override to customize rendering
	render: (gauge) ->
		@el.innerHTML = formatNumber(gauge.displayedValue, @fractionDigits)

class AnimatedText extends ValueUpdater
	displayedValue: 0
	value: 0

	setVal: (value) ->
		@value = 1 * value

	constructor: (@elem, @text=false) ->
		@value = 1 * @elem.innerHTML
		if @text
			@value = 0
	render: () ->
		if @text
			textVal = secondsToString(@displayedValue.toFixed(0))
		else
			textVal = addCommas(formatNumber(@displayedValue))
		@elem.innerHTML = textVal

AnimatedTextFactory =
	create: (objList) ->
		out = []
		for elem in objList
			out.push(new AnimatedText(elem))
		return out

class GaugePointer extends ValueUpdater
	displayedValue: 0
	value: 0
	options:
		strokeWidth: 0.035
		length: 0.1
		color: "#000000"

	constructor: (@gauge) ->
		@ctx = @gauge.ctx
		@canvas = @gauge.canvas
		super(false, false)
		@setOptions()

	setOptions: (options=null) ->
		updateObjectValues(@options, options)
		@length = 2*@gauge.radius * @options.length
		@strokeWidth = @canvas.height * @options.strokeWidth
		@maxValue = @gauge.maxValue
		@minValue = @gauge.minValue
		@animationSpeed =  @gauge.animationSpeed
		@options.angle = @gauge.options.angle

	render: () ->
		angle = @gauge.getAngle.call(@, @displayedValue)

		x = Math.round(@length * Math.cos(angle))
		y = Math.round(@length * Math.sin(angle))

		startX = Math.round(@strokeWidth * Math.cos(angle - Math.PI/2))
		startY = Math.round(@strokeWidth * Math.sin(angle - Math.PI/2))

		endX = Math.round(@strokeWidth * Math.cos(angle + Math.PI/2))
		endY = Math.round(@strokeWidth * Math.sin(angle + Math.PI/2))

		@ctx.fillStyle = @options.color
		@ctx.beginPath()

		@ctx.arc(0, 0, @strokeWidth, 0, Math.PI*2, true)
		@ctx.fill()

		@ctx.beginPath()
		@ctx.moveTo(startX, startY)
		@ctx.lineTo(x, y)
		@ctx.lineTo(endX, endY)
		@ctx.fill()

class Bar
	constructor: (@elem) ->
	updateValues: (arrValues) ->
		@value = arrValues[0]
		@maxValue = arrValues[1]
		@avgValue = arrValues[2]
		@render()

	render: () ->
		if @textField
			@textField.text(formatNumber(@value))

		if @maxValue == 0
			@maxValue = @avgValue * 2

		valPercent = (@value / @maxValue) * 100
		avgPercent = (@avgValue / @maxValue) * 100

		$(".bar-value", @elem).css({"width": valPercent + "%"})
		$(".typical-value", @elem).css({"width": avgPercent + "%"})

class Gauge extends BaseGauge
	elem: null
	value: [20] # we support multiple pointers
	maxValue: 80
	minValue: 0
	displayedAngle: 0
	displayedValue: 0
	lineWidth: 40
	paddingTop: 0.1
	paddingBottom: 0.1
	percentColors: null,
	options:
		colorStart: "#6fadcf"
		colorStop: undefined
		gradientType: 0       	# 0 : radial, 1 : linear
		strokeColor: "#e0e0e0"
		pointer:
			length: 0.8
			strokeWidth: 0.035
		angle: 0.15
		lineWidth: 0.44
		fontSize: 40
		limitMax: false

	constructor: (@canvas) ->
		super()
		@percentColors = null
		if typeof G_vmlCanvasManager != 'undefined'
			@canvas = window.G_vmlCanvasManager.initElement(@canvas)
		@ctx = @canvas.getContext('2d')
		# Set canvas size to parent size
		h = @canvas.clientHeight;
		w = @canvas.clientWidth;
		@canvas.height = h;
		@canvas.width = w;
		@gp = [new GaugePointer(@)]
		@setOptions()
		@render()

	setOptions: (options=null) ->
		super(options)
		@configPercentColors()
		@extraPadding = 0
		if @options.angle < 0
			phi = Math.PI*(1 + @options.angle)
			@extraPadding = Math.sin(phi)
		@availableHeight = @canvas.height * (1 - @paddingTop - @paddingBottom)
		@lineWidth = @availableHeight * @options.lineWidth # .2 - .7
		@radius = (@availableHeight - @lineWidth/2) / (1.0 + @extraPadding)
		@ctx.clearRect(0, 0, @canvas.width, @canvas.height)
		# @render()
		for gauge in @gp
			gauge.setOptions(@options.pointer)
			gauge.render()
		return @

	configPercentColors: () ->
		@percentColors = null;
		if (@options.percentColors != undefined)
			@percentColors = new Array()
			for i in [0..(@options.percentColors.length-1)]
				rval = parseInt((cutHex(@options.percentColors[i][1])).substring(0,2),16)
				gval = parseInt((cutHex(@options.percentColors[i][1])).substring(2,4),16)
				bval = parseInt((cutHex(@options.percentColors[i][1])).substring(4,6),16)
				@percentColors[i] = { pct: @options.percentColors[i][0], color: { r: rval, g: gval, b: bval  } }

	set: (value) ->
		if not (value instanceof Array)
			value = [value]
		# check if we have enough GaugePointers initialized
		# lazy initialization
		if value.length > @gp.length
			for i in [0...(value.length - @gp.length)]
				@gp.push(new GaugePointer(@))

		# get max value and update pointer(s)
		i = 0
		max_hit = false

		for val in value
			# Limit pointer within min and max?
			if @options.limitMax
				val = Math.min(Math.max(val, @minValue), @maxValue)
			else if val > @maxValue
				@maxValue = @value * 1.1
				max_hit = true
			@gp[i].value = val
			@gp[i++].setOptions({maxValue: @maxValue, angle: @options.angle})
		@value = value[value.length - 1] # TODO: Span maybe??

		if max_hit
			unless @options.limitMax
				AnimationUpdater.run()
		else
			AnimationUpdater.run()

	getAngle: (value) ->
		return (1 + @options.angle) * Math.PI + ((value - @minValue) / (@maxValue - @minValue)) * (1 - @options.angle * 2) * Math.PI

	getColorForPercentage: (pct, grad) ->
		if pct == 0
			color = @percentColors[0].color;
		else
			color = @percentColors[@percentColors.length - 1].color;
			for i in [0..(@percentColors.length - 1)]
				if (pct <= @percentColors[i].pct)
					if grad == true
						# Gradually change between colors
						startColor = @percentColors[i - 1] || @percentColors[0]
						endColor = @percentColors[i]
						rangePct = (pct - startColor.pct) / (endColor.pct - startColor.pct)  # How far between both colors
						color = {
							r: Math.floor(startColor.color.r * (1 - rangePct) + endColor.color.r * rangePct),
							g: Math.floor(startColor.color.g * (1 - rangePct) + endColor.color.g * rangePct),
							b: Math.floor(startColor.color.b * (1 - rangePct) + endColor.color.b * rangePct)
						}
					else
						color = @percentColors[i].color
					break
		return 'rgb(' + [color.r, color.g, color.b].join(',') + ')'

	getColorForValue: (val, grad) ->
		pct = (val - @minValue) / (@maxValue - @minValue)
		return @getColorForPercentage(pct, grad);

	renderStaticLabels: (staticLabels, w, h) ->
		@ctx.save()
		@ctx.translate(w, h)

		# Scale font size the hard way - assuming size comes first.
		font = staticLabels.font or "10px Times"
		re = /\d+\.?\d?/
		match = font.match(re)[0]
		rest = font.slice(match.length);
		fontsize = parseFloat(match) * this.displayScale;
		@ctx.font = fontsize + rest;

		@ctx.textBaseline = "bottom"
		@ctx.textAlign = "center"
		for value in staticLabels.labels
			rotationAngle = @getAngle(value) - 3*Math.PI/2
			@ctx.rotate(rotationAngle)
			@ctx.fillText(formatNumber(value, staticLabels.fractionDigits), 0, -@radius - @lineWidth/2)
			@ctx.rotate(-rotationAngle)
		@ctx.restore()

	render: () ->
		# Draw using canvas
		w = @canvas.width / 2
		h = @canvas.height*@paddingTop + @availableHeight - (@radius + @lineWidth/2)*@extraPadding
		displayedAngle = @getAngle(@displayedValue)
		if @textField
			@textField.render(@)

		@ctx.lineCap = "butt"
		
		if (@options.staticLabels)
			@renderStaticLabels(@options.staticLabels, w, h)

		if (@options.staticZones)
			@ctx.save()
			@ctx.translate(w, h)
			@ctx.lineWidth = @lineWidth
			for zone in @options.staticZones
				@ctx.strokeStyle = zone.strokeStyle
				@ctx.beginPath()
				@ctx.arc(0, 0, @radius, @getAngle(zone.min), @getAngle(zone.max), false)
				@ctx.stroke()
			@ctx.restore()

		else
			if @options.customFillStyle != undefined
				fillStyle = @options.customFillStyle(@)
			else if @percentColors != null
				fillStyle = @getColorForValue(@displayedValue, true)
			else if @options.colorStop != undefined
				if @options.gradientType == 0
					fillStyle = this.ctx.createRadialGradient(w, h, 9, w, h, 70);
				else
					fillStyle = this.ctx.createLinearGradient(0, 0, w, 0);
				fillStyle.addColorStop(0, @options.colorStart)
				fillStyle.addColorStop(1, @options.colorStop)
			else
				fillStyle = @options.colorStart
			@ctx.strokeStyle = fillStyle
		
			@ctx.beginPath()
			@ctx.arc(w, h, @radius, (1 + @options.angle) * Math.PI, displayedAngle, false)
			@ctx.lineWidth = @lineWidth
			@ctx.stroke()
	
			@ctx.strokeStyle = @options.strokeColor
			@ctx.beginPath()
			@ctx.arc(w, h, @radius, displayedAngle, (2 - @options.angle) * Math.PI, false)
			@ctx.stroke()


		# Draw pointers from (w, h)
		@ctx.translate(w, h)
		for gauge in @gp
			gauge.update(true)
		@ctx.translate(-w, -h)


class BaseDonut extends BaseGauge
	lineWidth: 15
	displayedValue: 0
	value: 33
	maxValue: 80
	minValue: 0

	options:
		lineWidth: 0.10
		colorStart: "#6f6ea0"
		colorStop: "#c0c0db"
		strokeColor: "#eeeeee"
		shadowColor: "#d5d5d5"
		angle: 0.35

	constructor: (@canvas) ->
		super()
		if typeof G_vmlCanvasManager != 'undefined'
			@canvas = window.G_vmlCanvasManager.initElement(@canvas)
		@ctx = @canvas.getContext('2d')
		@setOptions()
		@render()

	getAngle: (value) ->
		return (1 - @options.angle) * Math.PI + ((value - @minValue) / (@maxValue - @minValue)) * ((2 + @options.angle) - (1 - @options.angle)) * Math.PI

	setOptions: (options=null) ->
		super(options)
		@lineWidth = @canvas.height * @options.lineWidth
		@radius = @canvas.height / 2 - @lineWidth/2
		return @

	set: (value) ->
		@value = value
		if @value > @maxValue
			@maxValue = @value * 1.1
		AnimationUpdater.run()

	render: () ->
		displayedAngle = @getAngle(@displayedValue)
		w = @canvas.width / 2
		h = @canvas.height / 2

		if @textField
			@textField.render(@)

		grdFill = @ctx.createRadialGradient(w, h, 39, w, h, 70)
		grdFill.addColorStop(0, @options.colorStart)
		grdFill.addColorStop(1, @options.colorStop)

		start = @radius - @lineWidth / 2
		stop = @radius + @lineWidth / 2

		@ctx.strokeStyle = @options.strokeColor
		@ctx.beginPath()
		@ctx.arc(w, h, @radius, (1 - @options.angle) * Math.PI, (2 + @options.angle) * Math.PI, false)
		@ctx.lineWidth = @lineWidth
		@ctx.lineCap = "round"
		@ctx.stroke()

		@ctx.strokeStyle = grdFill
		@ctx.beginPath()
		@ctx.arc(w, h, @radius, (1 - @options.angle) * Math.PI, displayedAngle, false)
		@ctx.stroke()


class Donut extends BaseDonut
	strokeGradient: (w, h, start, stop) ->
		grd = @ctx.createRadialGradient(w, h, start, w, h, stop)
		grd.addColorStop(0, @options.shadowColor)
		grd.addColorStop(0.12, @options._orgStrokeColor)
		grd.addColorStop(0.88, @options._orgStrokeColor)
		grd.addColorStop(1, @options.shadowColor)
		return grd

	setOptions: (options=null) ->
		super(options)
		w = @canvas.width / 2
		h = @canvas.height / 2
		start = @radius - @lineWidth / 2
		stop = @radius + @lineWidth / 2
		@options._orgStrokeColor = @options.strokeColor
		@options.strokeColor = @strokeGradient(w, h, start, stop)
		return @

window.AnimationUpdater =
	elements: []
	animId: null

	addAll: (list) ->
		for elem in list
			AnimationUpdater.elements.push(elem)

	add: (object) ->
		AnimationUpdater.elements.push(object)

	run: () ->
		animationFinished = true
		for elem in AnimationUpdater.elements
			if elem.update()
				animationFinished = false
		if not animationFinished
			AnimationUpdater.animId = requestAnimationFrame(AnimationUpdater.run)
		else
			cancelAnimationFrame(AnimationUpdater.animId)

if typeof window.define == 'function' && window.define.amd?
	define(() ->
		{
			Gauge: Gauge,
			Donut: Donut,
			BaseDonut: BaseDonut,
			TextRenderer: TextRenderer
		}
	)
else if typeof module != 'undefined' && module.exports?
	module.exports = {
		Gauge: Gauge,
		Donut: Donut,
		BaseDonut: BaseDonut,
		TextRenderer: TextRenderer
	}
else
	window.Gauge = Gauge
	window.Donut = Donut
	window.BaseDonut = BaseDonut
	window.TextRenderer = TextRenderer
