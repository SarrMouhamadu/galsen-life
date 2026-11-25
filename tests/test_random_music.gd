extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("--- TEST CHARGEMENT ALÉATOIRE DES MUSIQUES ---")
	var audio = root.get_node("Audio")
	assert(audio != null, "L'autoload Audio doit exister")

	# 1. Vérification des pistes audio chargées
	print("Piste de démarrage choisie aléatoirement : [%d] %s" % [audio.current_track_idx, audio.TRACK_NAMES[audio.current_track_idx]])
	assert(audio.current_track_idx >= 0 and audio.current_track_idx < audio.TRACK_NAMES.size(), "current_track_idx doit être dans les bornes")
	
	var loaded_count := 0
	for s in audio._track_streams:
		if s != null:
			loaded_count += 1
	assert(loaded_count >= 5, "Au moins 5 morceaux de musique doivent être chargés")
	print("OK: %d morceaux de musique chargés dans la playlist" % loaded_count)

	# 2. Vérification que les MP3 ne sont pas en boucle unique figée (permettant le shuffle à la fin)
	for s in audio._track_streams:
		if s is AudioStreamMP3:
			assert((s as AudioStreamMP3).loop == false, "Les MP3 doivent avoir loop=false pour permettre l'enchaînement automatique")
	print("OK: Les flux MP3 sont configurés sans boucle figée pour le shuffle automatique")

	# 3. Test statistique de distribution aléatoire sur 100 tirages
	var counts := {}
	for i in audio._track_streams.size():
		if audio._track_streams[i] != null:
			counts[i] = 0

	for attempt in 100:
		var prev_idx: int = audio.current_track_idx
		audio.play_random_track(true)
		var new_idx: int = audio.current_track_idx
		assert(new_idx != prev_idx, "play_random_track(avoid_current=true) ne doit pas répéter le même morceau")
		counts[new_idx] = counts.get(new_idx, 0) + 1

	print("Répartition sur 100 tirages aléatoires :")
	for k in counts:
		print(" - Piste [%d] %s : %d fois" % [k, audio.TRACK_NAMES[k], counts[k]])
		assert(counts[k] > 0, "Chaque morceau disponible doit avoir été joué au moins une fois")
	print("OK: La sélection aléatoire est variée et équilibrée (aucun morceau bloqué)")

	# 4. Test du signal finished et enchaînement aléatoire
	var old_track: int = audio.current_track_idx
	audio._on_radio_finished()
	assert(audio.current_track_idx != old_track, "La fin d'un morceau doit enchaîner aléatoirement sur un nouveau morceau")
	print("OK: Enchaînement automatique après fin de morceau validé (passage à [%d] %s)" % [audio.current_track_idx, audio.TRACK_NAMES[audio.current_track_idx]])

	# 5. Test des contrôles radio
	audio.set_radio(false)
	assert(not audio.is_radio_playing(), "set_radio(false) doit éteindre la radio")
	audio.set_radio(true)
	assert(audio.is_radio_playing(), "set_radio(true) doit allumer la radio")
	print("OK: Contrôles marche/arrêt de la radio validés")

	print("--- TOUS LES TESTS DE MUSIQUE ALÉATOIRE SONT PASSÉS AVEC SUCCÈS ! ---")
	quit(0)
