extends Node
## Sons générés par le code (aucun fichier audio) : klaxon, moteur, sirène, pièces, radio mbalax.

const RATE := 22050

var _streams := {}
var _sfx: Array[AudioStreamPlayer] = []
var _next_sfx := 0
var _engine: AudioStreamPlayer
var _screech: AudioStreamPlayer
var _radio: AudioStreamPlayer
var _radio_wanted := false
var _radio_task := -1
var _track_samples: Array = [[], [], []]
var _track_streams: Array = [null, null, null, null, null, null, null]
var current_track_idx := 0
const TRACK_NAMES := [
	"🏅 JOJ Dakar 2026 (Hymne Officiel) — Baaba Maal",
	"🏅 Cérémonie d'Ouverture — JOJ Dakar 2026",
	"🏅 Générique JOJ 2026 — Iss 814 Beats",
	"🇸🇳 Niany Bagne Na — Kiné Lam",
	"🥁 Sabar, Tama & Mbeur (Ambiance Lamb & Arène)",
	"🇸🇳 Rythme Sabar & Tama (Bakk Sénégal)",
	"📻 Galsen Mbalax FM (Hits Dakar)",
]
const MUSIC_FILES := [
	"res://audio/music/baaba_maal_joj.mp3",
	"res://audio/music/dakar_2026_ceremony.mp3",
	"res://audio/music/iss814_joj.mp3",
	"res://audio/music/kine_lam_niany.mp3",
	"res://audio/music/sabar_tama_mbeur.mp3",
]
var _ambient_task := -1
var _ambient_samples := {}
var _pending_3d: Array = [] ## [lecteur, nom du son] en attente du calcul


func _ready() -> void:
	_streams["horn"] = _wav(_make_horn(), false)
	_streams["coin"] = _wav(_make_coin(), false)
	_streams["thud"] = _wav(_make_thud(), false)
	_streams["alert"] = _wav(_make_alert(), false)
	_streams["busted"] = _wav(_make_busted(), false)
	_streams["siren"] = _wav(_make_siren(), true)
	_streams["engine"] = _wav(_make_engine(), true)
	_streams["screech"] = _wav(_make_screech(), true)
	_streams["crash"] = _wav(_make_crash(), false)
	# Sons d'ambiance (pluie, tonnerre, vagues, foule) : calculés en arrière-plan
	_ambient_task = WorkerThreadPool.add_task(_build_ambient)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx.append(p)
	_engine = AudioStreamPlayer.new()
	_engine.stream = _streams["engine"]
	_engine.volume_db = -16.0
	add_child(_engine)
	_screech = AudioStreamPlayer.new()
	_screech.stream = _streams["screech"]
	_screech.volume_db = -60.0
	add_child(_screech)
	_radio = AudioStreamPlayer.new()
	_radio.volume_db = -9.0
	add_child(_radio)

	# Chargement des morceaux de musique officiels
	for i in MUSIC_FILES.size():
		var path: String = MUSIC_FILES[i]
		if ResourceLoader.exists(path):
			_track_streams[i] = load(path)
		elif FileAccess.file_exists(path):
			var s := AudioStreamMP3.new()
			s.data = FileAccess.get_file_as_bytes(path)
			s.loop = true
			_track_streams[i] = s

	# Musique principale par défaut au lancement du jeu (Baaba Maal dès 57s)
	if _track_streams[0] != null:
		_radio.stream = _track_streams[0]
		_radio_wanted = true
		_radio.play()

	# La boucle de mbalax synthétique se prépare en arrière-plan
	_radio_task = WorkerThreadPool.add_task(_build_radio)


func _process(_delta: float) -> void:
	if _ambient_task != -1 and WorkerThreadPool.is_task_completed(_ambient_task):
		_finish_ambient()
	if _radio_task != -1 and WorkerThreadPool.is_task_completed(_radio_task):
		WorkerThreadPool.wait_for_task_completion(_radio_task)
		_radio_task = -1
		_track_streams[5] = _wav(_track_samples[0], true)
		_track_streams[6] = _wav(_track_samples[2], true)
		if _radio.stream == null and _track_streams[current_track_idx] != null:
			_radio.stream = _track_streams[current_track_idx]
			if _radio_wanted:
				_radio.play()


func _exit_tree() -> void:
	# Fermeture rapide : on attend la fin des calculs en arrière-plan
	if _ambient_task != -1:
		WorkerThreadPool.wait_for_task_completion(_ambient_task)
	if _radio_task != -1:
		WorkerThreadPool.wait_for_task_completion(_radio_task)


func _build_ambient() -> void:
	_ambient_samples = {"thunder": [_make_thunder(), false], "rain": [_make_rain(), true],
		"waves": [_make_waves(), true], "crowd": [_make_crowd(), true]}


func _finish_ambient() -> void:
	WorkerThreadPool.wait_for_task_completion(_ambient_task)
	_ambient_task = -1
	for k in _ambient_samples:
		_streams[k] = _wav(_ambient_samples[k][0], _ambient_samples[k][1])
	_ambient_samples.clear()
	for e in _pending_3d:
		if is_instance_valid(e[0]):
			e[0].stream = _streams[e[1]]
			if e[0].is_inside_tree():
				e[0].play()
	_pending_3d.clear()


## Flux d'un son (null tant qu'il n'est pas encore calculé)
func stream(sound: String) -> AudioStream:
	return _streams.get(sound)


func radio_ready() -> bool:
	return _track_streams[0] != null


func is_radio_playing() -> bool:
	return _radio != null and _radio.playing


func play_sfx(sound: String, volume_db := -6.0) -> void:
	if not _streams.has(sound):
		return
	var p := _sfx[_next_sfx]
	_next_sfx = (_next_sfx + 1) % _sfx.size()
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.play()


## Son spatialisé (3D) en boucle : vagues, foule du marché, moteur d'une voiture...
func make_3d(sound: String, volume_db := 0.0, max_distance := 60.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.volume_db = volume_db
	p.max_distance = max_distance
	if _streams.has(sound):
		p.stream = _streams[sound]
	else:
		_pending_3d.append([p, sound])
	p.unit_size = 6.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.autoplay = true
	return p


func set_engine(on: bool, pitch := 1.0) -> void:
	if on:
		_engine.pitch_scale = clampf(pitch, 0.3, 3.5)
		if not _engine.playing:
			_engine.play()
	elif _engine.playing:
		_engine.stop()


## Volume du moteur selon l'accélérateur (0 : ralenti, 1 : pied au plancher)
func set_engine_load(load: float) -> void:
	_engine.volume_db = lerpf(-19.0, -11.0, clampf(load, 0.0, 1.0))


## Crissement des pneus : 0 (rien) → 1 (dérapage franc)
func set_screech(amount: float) -> void:
	if amount <= 0.02:
		if _screech.playing:
			_screech.stop()
		return
	_screech.volume_db = lerpf(-26.0, -8.0, clampf(amount, 0.0, 1.0))
	_screech.pitch_scale = lerpf(0.9, 1.15, clampf(amount, 0.0, 1.0))
	if not _screech.playing:
		_screech.play()


func set_radio(on: bool) -> void:
	_radio_wanted = on
	if on and _radio.stream != null and not _radio.playing:
		_radio.play()
	elif not on and _radio.playing:
		_radio.stop()


func set_radio_track(idx: int) -> void:
	current_track_idx = clampi(idx, 0, _track_streams.size() - 1)
	if _track_streams[current_track_idx] != null:
		var was_playing := _radio.playing or _radio_wanted
		_radio.stream = _track_streams[current_track_idx]
		if was_playing:
			_radio_wanted = true
			_radio.play()
	GameState.notify.emit("Radio : %s" % TRACK_NAMES[current_track_idx])


func next_radio_track() -> void:
	set_radio_track((current_track_idx + 1) % _track_streams.size())


func toggle_radio() -> void:
	if not _radio_wanted:
		set_radio(true)
		GameState.notify.emit("Radio : %s" % TRACK_NAMES[current_track_idx])
	else:
		current_track_idx += 1
		if current_track_idx >= _track_streams.size():
			current_track_idx = 0
			set_radio(false)
			GameState.notify.emit("Radio éteinte")
		else:
			set_radio_track(current_track_idx)


func make_siren_player() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _streams["siren"]
	p.unit_size = 14.0
	p.max_distance = 180.0
	p.volume_db = -4.0
	return p


func stop_all() -> void:
	set_engine(false)
	set_radio(false)
	for p in _sfx:
		p.stop()


# --- Synthèse ----------------------------------------------------------------

## Échantillons de garde après la fin : en boucle, le mixage de Godot lit un peu au-delà de loop_end
## (interpolation). Sur Android, un long son se termine pile avant une page protégée : sans ces
## échantillons le jeu plantait au premier tour de boucle (vagues, 8 s après leur départ).
const GUARD := 16

func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var n := samples.size()
	var bytes := PackedByteArray()
	bytes.resize((n + GUARD) * 2)
	for i in n + GUARD:
		# Garde : début de la boucle (raccord sans clic) ou silence pour un son joué une fois
		var s := samples[i] if i < n else (samples[(i - n) % n] if loop else 0.0)
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


static func _buffer(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


static func _env(i: int, n: int, attack := 0.01, release := 0.05) -> float:
	var t := float(i) / RATE
	var left := float(n - i) / RATE
	return minf(1.0, minf(t / attack, left / release))


## Pluie : bruit rose filtré + petites gouttes
func _make_rain() -> PackedFloat32Array:
	var b := _buffer(3.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.35
		lp2 += (lp - lp2) * 0.5
		var s := (lp - lp2 * 0.6) * 0.55
		if rng.randf() < 0.004:
			s += rng.randf_range(-0.4, 0.4)
		b[i] = s
	# Boucle sans clic : fondu sur les bords
	var f := 1500
	for i in f:
		var k := float(i) / f
		b[i] *= k
		b[b.size() - 1 - i] *= k
	return b


## Tonnerre : grondement grave qui roule
func _make_thunder() -> PackedFloat32Array:
	var b := _buffer(3.2)
	var rng := RandomNumberGenerator.new()
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.04
		var crack := rng.randf_range(-1.0, 1.0) * exp(-t * 18.0) * 0.5
		var roll := lp * 6.0 * exp(-t * 0.9) * (0.7 + 0.3 * sin(TAU * 2.3 * t))
		b[i] = clampf(roll + crack, -1.0, 1.0) * 0.9
	return b


## Vagues de l'Atlantique : souffle qui monte et retombe
func _make_waves() -> PackedFloat32Array:
	var b := _buffer(8.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
		var swell := pow(maxf(0.0, sin(TAU * t / 8.0 * 2.0)), 2.0) * 0.8 + 0.15
		b[i] = lp * 2.2 * swell
	return b


## Foule du marché : murmure de voix (formants qui varient)
func _make_crowd() -> PackedFloat32Array:
	var b := _buffer(6.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var voices := []
	for v in 7:
		voices.append([rng.randf_range(110.0, 260.0), rng.randf_range(0.0, TAU), rng.randf_range(1.5, 4.0)])
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var s := 0.0
		for v in voices:
			var syll := maxf(0.0, sin(TAU * v[2] * t + v[1]))
			s += sin(TAU * v[0] * t + 3.0 * sin(TAU * 5.0 * t + v[1])) * syll * 0.06
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.2
		b[i] = s + lp * 0.08
	return b


func _make_horn() -> PackedFloat32Array:
	var b := _buffer(0.45)
	for i in b.size():
		var t := float(i) / RATE
		var s := signf(sin(TAU * 370.0 * t)) * 0.25 + signf(sin(TAU * 466.0 * t)) * 0.25
		s += sin(TAU * 370.0 * t) * 0.2
		b[i] = s * _env(i, b.size()) * 0.7
	return b


func _make_coin() -> PackedFloat32Array:
	var b := _buffer(0.3)
	for i in b.size():
		var t := float(i) / RATE
		var f := 1320.0 if t < 0.07 else 1760.0
		var t2 := t if t < 0.07 else t - 0.07
		b[i] = sin(TAU * f * t) * exp(-t2 * 14.0) * 0.5
	return b


func _make_thud() -> PackedFloat32Array:
	var b := _buffer(0.3)
	var rng := RandomNumberGenerator.new()
	for i in b.size():
		var t := float(i) / RATE
		b[i] = sin(TAU * 90.0 * t) * exp(-t * 14.0) * 0.8 + rng.randf_range(-1.0, 1.0) * exp(-t * 60.0) * 0.5
	return b


## Crissement de pneus : bruit filtré et sifflement qui ondule (boucle d'une seconde)
func _make_screech() -> PackedFloat32Array:
	var b := _buffer(1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lp := 0.0
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.35)
		ph += TAU * (1700.0 + 180.0 * sin(TAU * 6.0 * t) + 90.0 * sin(TAU * 13.0 * t)) / RATE
		b[i] = (sin(ph) * 0.35 + lp * 0.4) * (0.8 + 0.2 * sin(TAU * 3.0 * t))
	return b


## Accident : choc sourd, tôle froissée et débris de verre
func _make_crash() -> PackedFloat32Array:
	var b := _buffer(0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in b.size():
		var t := float(i) / RATE
		var thump := sin(TAU * 70.0 * t) * exp(-t * 9.0) * 0.9
		var metal := sin(TAU * (420.0 + 60.0 * sin(TAU * 23.0 * t)) * t) * exp(-t * 5.0) * 0.25
		var glass := (rng.randf_range(-1.0, 1.0) * 0.35 if rng.randf() < 0.08 else 0.0) * exp(-t * 3.0)
		var noise := rng.randf_range(-1.0, 1.0) * exp(-t * 18.0) * 0.6
		b[i] = clampf(thump + metal + glass + noise, -1.0, 1.0)
	return b


func _make_alert() -> PackedFloat32Array:
	var b := _buffer(0.36)
	for i in b.size():
		var t := float(i) / RATE
		var on := fmod(t, 0.18) < 0.12
		b[i] = (sin(TAU * 990.0 * t) * 0.4 if on else 0.0) * _env(i, b.size())
	return b


func _make_busted() -> PackedFloat32Array:
	var notes := [660.0, 520.0, 390.0]
	var b := _buffer(0.75)
	for i in b.size():
		var t := float(i) / RATE
		var k := mini(int(t / 0.22), 2)
		var f: float = notes[k]
		b[i] = (signf(sin(TAU * f * t)) * 0.2 + sin(TAU * f * t) * 0.2) * exp(-(t - k * 0.22) * 4.0) * _env(i, b.size())
	return b


## Sirène « wail » : la fréquence monte et descend toutes les 2 secondes.
func _make_siren() -> PackedFloat32Array:
	var b := _buffer(2.0)
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 650.0 + 550.0 * (0.5 - 0.5 * cos(TAU * t / 2.0))
		phase += TAU * f / RATE
		b[i] = (sin(phase) * 0.45 + sin(phase * 2.0) * 0.12)
	return b


## Bourdonnement de moteur : 55 cycles exacts par seconde pour une boucle sans clic.
func _make_engine() -> PackedFloat32Array:
	var b := _buffer(1.0)
	for i in b.size():
		var t := float(i) / RATE
		var ph := TAU * 55.0 * t
		var s := sin(ph) * 0.5 + sin(ph * 2.0) * 0.3 + sin(ph * 3.0) * 0.18 + sin(ph * 5.0) * 0.08
		b[i] = s * (0.75 + 0.25 * sin(TAU * 4.0 * t)) * 0.6
	return b


## Génération multicanal des 3 pistes musicales en arrière-plan :
## 0: 🇸🇳 Rythme Sabar & Tama (Bakk Sénégal)
## 1: 🏅 JOJ Dakar 2026 (Hymne d'Ouverture)
## 2: 📻 Galsen Mbalax FM (Hits Dakar)
func _build_radio() -> void:
	_track_samples[0] = _build_sabar_track()
	_track_samples[1] = _build_joj_track()
	_track_samples[2] = _build_mbalax_track()


## Piste 0 : Rythme traditionnel Sabar & Tama des arènes dakaroises (Bakk, Thiol, Mbëng-mbëng, Tama parlant)
func _build_sabar_track() -> PackedFloat32Array:
	var bpm := 140.0
	var step := 60.0 / bpm / 4.0
	var steps := 64 # 4 mesures complètes
	var n := int(step * steps * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 313

	# Sabar Thiol (grosse percussion basse résonante)
	var thiol_steps := [0, 4, 8, 10, 14, 16, 20, 24, 26, 30, 32, 36, 40, 42, 46]
	for s in thiol_steps:
		var t0 := int(s * step * RATE)
		buf = _drum(buf, t0, 105.0, 52.0, 0.22, 0.70)

	# Claquements secs de baguette Sabar (Gal / Mbëng-mbëng)
	var slap_steps := [2, 6, 7, 11, 12, 15, 18, 22, 23, 27, 28, 31, 34, 38, 39, 43, 44, 47]
	for s in slap_steps:
		var t0 := int(s * step * RATE)
		buf = _slap(buf, t0, rng, 0.50)

	# Tama parlant (variations de hauteur caractéristiques sous l'aisselle)
	var tama_bends := [
		[3, 220.0, 370.0, 0.16, 0.60],
		[5, 410.0, 260.0, 0.14, 0.55],
		[9, 240.0, 420.0, 0.18, 0.65],
		[13, 380.0, 240.0, 0.15, 0.55],
		[19, 210.0, 350.0, 0.16, 0.60],
		[21, 440.0, 290.0, 0.14, 0.55],
		[25, 230.0, 400.0, 0.17, 0.65],
		[29, 390.0, 250.0, 0.15, 0.55],
		[35, 220.0, 360.0, 0.16, 0.60],
		[37, 430.0, 280.0, 0.14, 0.55],
		[41, 240.0, 410.0, 0.18, 0.65],
		[45, 380.0, 250.0, 0.15, 0.55]
	]
	for tb in tama_bends:
		var t0 := int(float(tb[0]) * step * RATE)
		buf = _tama(buf, t0, float(tb[1]), float(tb[2]), float(tb[3]), float(tb[4]))

	# 4ème mesure : Bàkk traditionnel wolof (roulement accéléré et cadences rituelles des lutteurs)
	var bakk_steps := [48, 50, 52, 53, 54, 56, 58, 60, 61, 62, 63]
	for s in bakk_steps:
		var t0 := int(s * step * RATE)
		if s % 2 == 0:
			buf = _drum(buf, t0, 130.0, 62.0, 0.14, 0.75)
		else:
			buf = _slap(buf, t0, rng, 0.60)
		if s >= 56:
			buf = _tama(buf, t0, 280.0 + (s - 56) * 40.0, 420.0 + (s - 56) * 30.0, 0.10, 0.60)

	# Ligne mélodique subtile de Kora (gamme pentatonique mandingue / wolof)
	var kora_notes := [293.7, 349.2, 392.0, 440.0, 523.3]
	var kora_pattern := [0, -1, 1, 2, -1, 3, 2, 1, 0, -1, 4, 3, -1, 2, 1, 0]
	for bar in 3:
		for s in 16:
			var note_idx: int = kora_pattern[s]
			if note_idx >= 0:
				var t0 := int((bar * 16 + s) * step * RATE)
				buf = _kora(buf, t0, kora_notes[note_idx], 0.25)

	return _normalize_track(buf)


## Piste 1 : Hymne triomphal d'ouverture des JOJ Dakar 2026 (Cuivres olympiques, percussions modernes & ferveur africaine)
func _build_joj_track() -> PackedFloat32Array:
	var bpm := 122.0
	var step := 60.0 / bpm / 4.0
	var steps := 64 # 4 mesures
	var n := int(step * steps * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026

	# Accords de cuivres héroïques (Fanfare Olympique)
	var chords := [
		[0, [174.6, 220.0, 261.6, 349.2], 0.85, 0.45],
		[8, [174.6, 220.0, 261.6, 349.2], 0.70, 0.40],
		[16, [130.8, 196.0, 261.6, 329.6], 0.85, 0.45],
		[24, [130.8, 196.0, 261.6, 329.6], 0.70, 0.40],
		[32, [146.8, 220.0, 293.7, 349.2], 0.85, 0.45],
		[40, [146.8, 220.0, 293.7, 349.2], 0.70, 0.40],
		[48, [116.5, 174.6, 233.1, 293.7], 0.75, 0.45],
		[54, [116.5, 174.6, 233.1, 293.7], 0.50, 0.38],
		[56, [130.8, 196.0, 261.6, 329.6], 0.85, 0.48],
		[60, [130.8, 196.0, 261.6, 329.6], 0.55, 0.40]
	]
	for c in chords:
		var t0 := int(float(c[0]) * step * RATE)
		buf = _brass(buf, t0, c[1], float(c[2]), float(c[3]))

	# Thème mélodique principal de la jeunesse africaine (Lead cuivres / synthétiseur triomphal)
	var theme_notes := [
		[0, 523.3, 0.22, 0.45],
		[2, 698.5, 0.22, 0.48],
		[4, 880.0, 0.45, 0.52],
		[8, 784.0, 0.35, 0.48],
		[12, 698.5, 0.35, 0.45],
		[16, 659.3, 0.35, 0.45],
		[20, 784.0, 0.35, 0.48],
		[24, 523.3, 0.55, 0.50],
		[32, 587.3, 0.25, 0.45],
		[36, 698.5, 0.25, 0.48],
		[40, 880.0, 0.45, 0.52],
		[44, 587.3, 0.35, 0.45],
		[48, 587.3, 0.25, 0.45],
		[52, 698.5, 0.25, 0.48],
		[56, 784.0, 0.30, 0.50],
		[60, 880.0, 0.30, 0.52],
		[62, 1046.5, 0.40, 0.58]
	]
	for tn in theme_notes:
		var t0 := int(float(tn[0]) * step * RATE)
		buf = _lead_synth(buf, t0, float(tn[1]), float(tn[2]), float(tn[3]))

	# Rythmique moderne de stade : Kick percutant sur les 4 temps
	for s in range(0, steps, 4):
		var t0 := int(s * step * RATE)
		buf = _drum(buf, t0, 120.0, 48.0, 0.20, 0.70)

	# Caisse claire puissante de stade + battement de mains (claps) sur 2 et 4
	for s in range(4, steps, 8):
		var t0 := int(s * step * RATE)
		buf = _snare(buf, t0, rng, 0.65)

	# Charlestons réguliers (hi-hat)
	for s in range(2, steps, 2):
		var t0 := int(s * step * RATE)
		buf = _hihat(buf, t0, rng, 0.25 if s % 4 == 2 else 0.15)

	# Transition Sabar & Tama sénégalaise en fin de cycle (fierté dakaroise)
	for s in [60, 61, 62, 63]:
		var t0 := int(s * step * RATE)
		buf = _tama(buf, t0, 320.0 + (s - 60) * 45.0, 480.0, 0.10, 0.55)

	return _normalize_track(buf)


## Piste 2 : Galsen Mbalax FM (Hits Dakar - balafon pentatonique, guitare mbalax, sabar urbain)
func _build_mbalax_track() -> PackedFloat32Array:
	var bpm := 132.0
	var step := 60.0 / bpm / 4.0
	var steps := 64
	var n := int(step * steps * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var tama_steps := [0, 3, 6, 8, 10, 11, 14]
	var slap_steps := [2, 7, 12, 15]
	var bass_steps := [0, 6, 10]
	var notes := [261.6, 293.7, 329.6, 392.0, 440.0, 523.3, 587.3]
	var melody := [4, 3, 4, 2, 4, 5, 4, 3, 2, 3, 2, 0, 2, 3, 4, -1]
	var rng := RandomNumberGenerator.new()
	rng.seed = 221
	for s in steps:
		var bs := s % 16
		var t0 := int(s * step * RATE)
		if bs in tama_steps:
			buf = _drum(buf, t0, 330.0, 190.0, 0.12, 0.55 if bs == 0 else 0.35)
		if bs in slap_steps:
			buf = _slap(buf, t0, rng, 0.45)
		if bs in bass_steps:
			buf = _drum(buf, t0, 110.0, 55.0, 0.25, 0.6)
		if s % 2 == 0:
			var m: int = melody[(s / 2) % melody.size()]
			if m >= 0:
				var f: float = notes[m] * (1.5 if s >= 32 and m < 3 else 1.0)
				buf = _pluck(buf, t0, f, 0.25)
	return _normalize_track(buf)


static func _normalize_track(buf: PackedFloat32Array) -> PackedFloat32Array:
	var peak := 0.001
	for v in buf:
		peak = maxf(peak, absf(v))
	var n := buf.size()
	for i in n:
		buf[i] = buf[i] / peak * 0.82
	return buf


static func _drum(buf: PackedFloat32Array, start: int, f0: float, f1: float, dur: float, amp: float) -> PackedFloat32Array:
	var n := buf.size()
	var count := int(dur * RATE)
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		var f := f1 + (f0 - f1) * exp(-t * 40.0)
		phase += TAU * f / RATE
		var k := (start + i) % n
		buf[k] += sin(phase) * exp(-t / (dur * 0.3)) * amp
	return buf


static func _tama(buf: PackedFloat32Array, start: int, f0: float, f1: float, dur: float, amp: float) -> PackedFloat32Array:
	var n := buf.size()
	var count := int(dur * RATE)
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		var bend := 1.0 - exp(-t * 22.0)
		var f := f0 + (f1 - f0) * bend
		phase += TAU * f / RATE
		var k := (start + i) % n
		var env := exp(-t / (dur * 0.35))
		buf[k] += (sin(phase) + 0.35 * sin(phase * 2.0) + 0.15 * sin(phase * 3.0)) * env * amp
	return buf


static func _slap(buf: PackedFloat32Array, start: int, rng: RandomNumberGenerator, amp := 0.5) -> PackedFloat32Array:
	var n := buf.size()
	var count := int(0.06 * RATE)
	for i in count:
		var t := float(i) / RATE
		var k := (start + i) % n
		var noise := rng.randf_range(-1.0, 1.0) * 0.4
		var strike := sin(TAU * 680.0 * t) * 0.35
		buf[k] += (noise + strike) * exp(-t / 0.015) * amp
	return buf


static func _pluck(buf: PackedFloat32Array, start: int, f: float, amp: float) -> PackedFloat32Array:
	var n := buf.size()
	var count := int(0.3 * RATE)
	for i in count:
		var t := float(i) / RATE
		var k := (start + i) % n
		buf[k] += (sin(TAU * f * t) * exp(-t / 0.18) + sin(TAU * f * 3.9 * t) * 0.35 * exp(-t / 0.05)) * amp
	return buf


static func _kora(buf: PackedFloat32Array, start: int, f: float, amp: float) -> PackedFloat32Array:
	var n := buf.size()
	var count := int(0.35 * RATE)
	for i in count:
		var t := float(i) / RATE
		var k := (start + i) % n
		var s := sin(TAU * f * t) * exp(-t / 0.22) + sin(TAU * f * 2.76 * t) * 0.3 * exp(-t / 0.08)
		buf[k] += s * amp
	return buf


static func _brass(buf: PackedFloat32Array, start: int, freqs: Array, dur: float, amp: float) -> PackedFloat32Array:
	var n := buf.size()
	var count := int(dur * RATE)
	var chord_size := maxf(1.0, float(freqs.size()))
	for item in freqs:
		var f: float = item
		var phase := 0.0
		for i in count:
			var t := float(i) / RATE
			phase += TAU * f / RATE
			var attack := minf(1.0, t / 0.035)
			var decay := exp(-t / (dur * 0.7))
			var s := sin(phase) + 0.45 * sin(phase * 2.0) + 0.25 * sin(phase * 3.0) + 0.12 * sin(phase * 4.0)
			var k := (start + i) % n
			buf[k] += s * attack * decay * (amp / chord_size)
	return buf


static func _lead_synth(buf: PackedFloat32Array, start: int, f: float, dur: float, amp: float) -> PackedFloat32Array:
	var n := buf.size()
	var count := int(dur * RATE)
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		phase += TAU * f / RATE
		var attack := minf(1.0, t / 0.02)
		var decay := exp(-t / (dur * 0.6))
		var s := sin(phase) + 0.5 * sin(phase * 2.0) + 0.2 * sin(phase * 3.0)
		var k := (start + i) % n
		buf[k] += s * attack * decay * amp
	return buf


static func _snare(buf: PackedFloat32Array, start: int, rng: RandomNumberGenerator, amp: float) -> PackedFloat32Array:
	var n := buf.size()
	var count := int(0.18 * RATE)
	for i in count:
		var t := float(i) / RATE
		var k := (start + i) % n
		var tone := sin(TAU * 185.0 * t) * exp(-t / 0.04) * 0.4
		var snap := rng.randf_range(-1.0, 1.0) * exp(-t / 0.08) * 0.6
		buf[k] += (tone + snap) * amp
	return buf


static func _hihat(buf: PackedFloat32Array, start: int, rng: RandomNumberGenerator, amp: float) -> PackedFloat32Array:
	var n := buf.size()
	var count := int(0.04 * RATE)
	for i in count:
		var t := float(i) / RATE
		var k := (start + i) % n
		var snap := rng.randf_range(-1.0, 1.0) * exp(-t / 0.012)
		buf[k] += snap * amp
	return buf
