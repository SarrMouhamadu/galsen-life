extends Node
## Chat vocal du mode en ligne.
## - Maintenir V (ou le bouton MICRO) : parler aux joueurs proches (voix spatialisée, portée Net.VOICE_RANGE).
## - Maintenir B (ou le bouton RADIO) : radio du groupe, entendue par tous les membres, même de loin.
## Le micro est capturé (bus « Micro » muet + AudioEffectCapture), réduit à 8 000 échantillons/s
## et compressé en μ-law (8 bits par échantillon, qualité téléphone : ~8 Ko/s quand on parle).
## Le serveur ne relaie la voix qu'aux joueurs concernés ; chaque voix est jouée à la position de l'avatar.

const RATE := 8000
const CHUNK := 0.1 ## secondes de son par paquet
const BUS := "Micro"

var main
var talking := "" ## "" (silence), "local" ou "group"
var enabled := true
var _capture: AudioEffectCapture
var _mic: AudioStreamPlayer
var _players := {} ## id du joueur qui parle → {player, playback, until}
var _send_t := 0.0
var _mic_ok := false
static var _ulaw_decode := PackedFloat32Array()


func _ready() -> void:
	_build_tables()
	Net.voice_received.connect(_on_voice)
	_setup_mic()


static func _build_tables() -> void:
	if not _ulaw_decode.is_empty():
		return
	_ulaw_decode.resize(256)
	for i in 256:
		_ulaw_decode[i] = _ulaw_to_float(i)


## Micro : bus muet avec capture (on n'entend pas sa propre voix).
## Le micro n'est allumé que pendant qu'on parle : allumé en continu, il faisait planter certains
## téléphones Android au bout d'un moment (tampon d'entrée du pilote son corrompu).
func _setup_mic() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var idx := AudioServer.get_bus_index(BUS)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS)
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.5
		AudioServer.add_bus_effect(idx, _capture)
		AudioServer.set_bus_mute(idx, true)
	else:
		_capture = AudioServer.get_bus_effect(idx, 0)
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = BUS
	add_child(_mic)
	_mic_ok = true


## Micro : autorisation d'accès (Android et iOS)
static func _mic_allowed() -> bool:
	if OS.has_feature("android"):
		return OS.request_permission("android.permission.RECORD_AUDIO")
	if OS.has_feature("ios"):
		# Sur iOS, Godot déclenche la demande via Info.plist (NSMicrophoneUsageDescription).
		if OS.has_method("request_permission"):
			return OS.request_permission("RECORD_AUDIO")
		return true
	return true


## Début / fin de prise de parole (touche ou bouton)
func start_talking(channel: String) -> void:
	if not Net.online or not enabled:
		return
	if channel == "group" and Net.social.my_group == "":
		GameState.notify.emit("Tu n'as pas de groupe pour la radio (téléphone → Mbokk).")
		return
	if not _mic_ok:
		GameState.notify.emit("Micro indisponible.")
		return
	if not _mic_allowed():
		GameState.notify.emit("Autorise l'accès au micro, puis appuie de nouveau pour parler.")
		return
	talking = channel
	if _capture:
		_capture.clear_buffer()
	if not _mic.playing:
		_mic.play()


func stop_talking() -> void:
	if talking != "" and _capture and _capture.get_frames_available() > 0:
		Net.send_voice(encode(_capture.get_buffer(_capture.get_frames_available()), AudioServer.get_mix_rate()), talking)
	talking = ""
	if _mic and _mic.playing:
		_mic.stop()


func toggle_talking(channel := "local") -> void:
	if talking == channel:
		stop_talking()
	else:
		start_talking(channel)


func _process(delta: float) -> void:
	if not Net.online:
		if talking != "":
			talking = ""
			if _mic:
				_mic.stop()
		return
	# Touches (le clavier ne sert pas pendant qu'on écrit)
	if not GameState.typing:
		if Input.is_action_just_pressed("voice"):
			start_talking("local")
		elif Input.is_action_just_released("voice") and talking == "local":
			stop_talking()
		if Input.is_action_just_pressed("voice_group"):
			start_talking("group")
		elif Input.is_action_just_released("voice_group") and talking == "group":
			stop_talking()
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = CHUNK
		if talking != "" and _capture:
			var frames := _capture.get_buffer(_capture.get_frames_available())
			if not frames.is_empty():
				Net.send_voice(encode(frames, AudioServer.get_mix_rate()), talking)
		elif _capture:
			_capture.clear_buffer()
	# Voix qui se sont tues : on libère les lecteurs
	var now := Time.get_ticks_msec()
	for id in _players.keys():
		if now > int(_players[id]["until"]):
			_players[id]["player"].queue_free()
			_players.erase(id)


## Stéréo flottante au débit du mixeur → μ-law 8 kHz
static func encode(frames: PackedVector2Array, mix_rate: float) -> PackedByteArray:
	var out := PackedByteArray()
	var step := mix_rate / RATE
	var n := int(frames.size() / step)
	out.resize(n)
	var pos := 0.0
	for i in n:
		var a := int(pos)
		var b := mini(frames.size(), int(pos + step))
		var acc := 0.0
		for k in range(a, maxi(a + 1, b)):
			acc += (frames[k].x + frames[k].y) * 0.5
		acc /= maxf(1.0, b - a)
		out[i] = _float_to_ulaw(clampf(acc * 1.6, -1.0, 1.0))
		pos += step
	return out


static func decode(data: PackedByteArray) -> PackedFloat32Array:
	_build_tables()
	var out := PackedFloat32Array()
	out.resize(data.size())
	for i in data.size():
		out[i] = _ulaw_decode[data[i]]
	return out


static func _float_to_ulaw(x: float) -> int:
	var s := int(x * 32767.0)
	var sign := 0
	if s < 0:
		sign = 0x80
		s = -s
	s = mini(s + 132, 32635)
	var exponent := 7
	var mask := 0x4000
	while exponent > 0 and (s & mask) == 0:
		exponent -= 1
		mask >>= 1
	var mantissa := (s >> (exponent + 3)) & 0x0F
	return (~(sign | (exponent << 4) | mantissa)) & 0xFF


static func _ulaw_to_float(u: int) -> float:
	u = (~u) & 0xFF
	var sign := u & 0x80
	var exponent := (u >> 4) & 0x07
	var mantissa := u & 0x0F
	var s := (((mantissa << 3) + 132) << exponent) - 132
	return float(-s if sign != 0 else s) / 32768.0


# --- Réception ------------------------------------------------------------------------

func _on_voice(sender: int, data: PackedByteArray, channel: String) -> void:
	if not enabled:
		return
	var samples := decode(data)
	if not _players.has(sender):
		var p: Node
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = RATE
		gen.buffer_length = 0.6
		if channel == "local" and main.remote_players.holder_of(sender) != null:
			# Voix de proximité : elle vient de l'avatar du joueur
			var p3 := AudioStreamPlayer3D.new()
			p3.unit_size = 6.0
			p3.max_distance = Net.VOICE_RANGE + 10.0
			p3.volume_db = 4.0
			main.remote_players.holder_of(sender).add_child(p3)
			p3.position = Vector3(0, 1.6, 0)
			p = p3
		else:
			# Radio du groupe : partout, comme un talkie-walkie
			var p2 := AudioStreamPlayer.new()
			p2.volume_db = -2.0
			add_child(p2)
			p = p2
		p.stream = gen
		p.play()
		_players[sender] = {"player": p, "playback": p.get_stream_playback(), "until": 0}
	var e: Dictionary = _players[sender]
	e["until"] = Time.get_ticks_msec() + 1500
	var pb = e["playback"]
	if pb == null:
		return # (sans carte son : rien à jouer)
	var room: int = pb.get_frames_available()
	for i in mini(samples.size(), room):
		pb.push_frame(Vector2(samples[i], samples[i]))
	main.remote_players.set_talking(sender, channel)


func is_speaking(id: int) -> bool:
	return _players.has(id)
