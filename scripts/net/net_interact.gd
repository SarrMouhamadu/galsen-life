extends Node
## Actions avec les autres joueurs en ligne (touche d'action près d'eux) :
## monter comme passager dans leur voiture, leur donner de l'argent, les arrêter (police),
## les relever quand ils sont à terre (SAMU), leur proposer un échange (scripts/net/net_trade.gd).

const RANGE_FOOT := 3.0
const RANGE_CAR := 5.0
const AMOUNTS := [500, 1000, 2000, 5000, 10000]

var main


func _target() -> Variant:
	var p = main.player
	if not Net.online or p.current_vehicle != null or p.riding != null or main.hud.choices_open():
		return null
	var o = main.remote_players.nearest(p.global_position, RANGE_CAR)
	if o == null:
		return null
	if o["vehicle"] == null and o["pos"].distance_to(p.global_position) > RANGE_FOOT:
		return null
	return o


func get_hint() -> String:
	var o = _target()
	if o == null:
		return ""
	if main.net_jobs.can_heal(o["id"]):
		return "Soigner " + o["pseudo"]
	if GameState.rp_job == "police" and o["wl"] > 0:
		return "Arrêter " + o["pseudo"]
	if GameState.rp_job == "mecanicien":
		return "Réparer le véhicule de " + o["pseudo"]
	if GameState.rp_job == "police":
		return "Contrôle de police : " + o["pseudo"]
	if o["vehicle"] != null:
		return ("Prendre le taxi de " if o["job"] == "taxi" else "Monter / Discuter avec ") + o["pseudo"]
	return ("Acheter à " if o["job"] == "vendeur" else "💬 Discuter / Interagir avec ") + o["pseudo"]


func try_interact() -> bool:
	var o = _target()
	if o == null:
		return false
	var id: int = o["id"]
	var who: String = o["pseudo"]
	var choices: Array = []
	choices.append(["💬 Discuter avec %s" % who, func(): main.hud.open_chat_direct(who)])
	var jobs = main.net_jobs
	if jobs.can_heal(id):
		Net.factions.heal(id)
		GameState.notify.emit("Tu soignes %s..." % who)
		return true
	if GameState.rp_job == "mecanicien":
		choices.append(["Réparer et faire le plein du véhicule de %s (%s)" % [who, GameState.fcfa(jobs.REPAIR_PRICE)], func():
			Net.city.service(id)
			GameState.notify.emit("Tu répares le véhicule de %s..." % who)])
	if GameState.rp_job == "police":
		for r in Net.city.TICKETS:
			var reason: String = r
			choices.append(["PV à %s : %s (%s)" % [who, reason.to_lower(), GameState.fcfa(Net.city.TICKETS[reason])], func():
				Net.city.ticket(id, reason)
				GameState.notify.emit("Tu dresses un PV à %s : %s." % [who, reason.to_lower()])])
	if GameState.rp_job == "police" and o["wl"] > 0:
		choices.append(["Arrêter %s (%s)" % [who, "*".repeat(o["wl"])], func(): Net.arrest(id)])
	if o["vehicle"] != null and o["job"] == "taxi":
		var v = o["vehicle"]
		choices.append(["Prendre le taxi de %s (choisir la destination)" % who, func(): jobs.take_taxi(id, who, v)])
	if o["vehicle"] == null and o["job"] == "vendeur":
		choices.append(["Acheter à %s" % who, func(): jobs.buy_from(id, who)])
	if o["vehicle"] != null:
		choices.append(["Monter dans la voiture de %s" % who, func(): _ride(id, who)])
	elif main.social_ui and main.social_ui.duel_with < 0:
		for st in [0, 1000, 5000]:
			var stake: int = st
			choices.append(["Défier à la lutte (%s)" % ("sans mise" if stake == 0 else "mise " + GameState.fcfa(stake)), func(): main.social_ui.challenge(id, stake)])
	if Net.trade and not Net.trade.in_trade():
		choices.append(["Proposer un échange à %s (objets, argent, véhicules)" % who, func(): Net.trade.propose(id)])
	for a in AMOUNTS:
		var amount: int = a
		choices.append(["Donner %s" % GameState.fcfa(amount), func(): _give(id, who, amount)])
	main.hud.show_choices(who, choices, func(): pass)
	return true


func _ride(id: int, who: String) -> void:
	var o = main.remote_players.nearest(main.player.global_position, RANGE_CAR + 3.0)
	if o == null or o["id"] != id or o["vehicle"] == null:
		GameState.notify.emit("%s est parti sans toi." % who)
		return
	main.player.ride(o["vehicle"])
	Net.notify_ride(id)
	GameState.notify.emit("Tu montes avec %s. Appuie sur l'action pour descendre." % who)


func _give(id: int, who: String, amount: int) -> void:
	if not Net.roster.has(id):
		GameState.notify.emit("%s n'est plus en ligne." % who)
	elif Net.give_money(id, amount):
		GameState.notify.emit("Tu as donné %s à %s." % [GameState.fcfa(amount), who])
	else:
		GameState.notify.emit("Tu n'as pas assez d'argent.")
