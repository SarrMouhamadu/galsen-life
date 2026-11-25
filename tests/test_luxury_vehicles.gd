extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("--- TEST AUTOS ET MOTOS DE LUXE ---")
	var VehicleScript = load("res://scripts/vehicles/vehicle.gd")
	var Dealership = load("res://scripts/vehicles/dealership.gd")
	var Rental = load("res://scripts/vehicles/rental.gd")
	
	# 1. Vérification des types et noms de prestige
	assert(VehicleScript.TYPES.has("clando"), "Type clando manquant")
	assert("Luxe" in VehicleScript.TYPES["clando"]["name"] or "VIP" in VehicleScript.TYPES["clando"]["name"], "clando doit être une voiture de luxe")
	assert(VehicleScript.TYPES["clando"]["speed"] >= 30.0, "Vitesse de la berline de luxe doit être >= 30 m/s")
	print("OK: Berline de luxe validée (%s, %s m/s)" % [VehicleScript.TYPES["clando"]["name"], VehicleScript.TYPES["clando"]["speed"]])
	
	assert(VehicleScript.TYPES.has("suv"), "Type suv manquant")
	assert("SUV" in VehicleScript.TYPES["suv"]["name"] and "Luxe" in VehicleScript.TYPES["suv"]["name"], "suv doit être un SUV de luxe")
	print("OK: SUV de luxe validé (%s, %s m/s)" % [VehicleScript.TYPES["suv"]["name"], VehicleScript.TYPES["suv"]["speed"]])
	
	assert(VehicleScript.TYPES.has("jakarta"), "Type jakarta manquant")
	assert("T-MAX" in VehicleScript.TYPES["jakarta"]["name"] or "Luxe" in VehicleScript.TYPES["jakarta"]["name"], "jakarta doit être une moto de luxe (T-MAX)")
	assert(VehicleScript.TYPES["jakarta"]["speed"] >= 30.0, "Vitesse du T-MAX de luxe doit être >= 30 m/s")
	print("OK: Maxi-scooter T-MAX validé (%s, %s m/s)" % [VehicleScript.TYPES["jakarta"]["name"], VehicleScript.TYPES["jakarta"]["speed"]])
	
	assert(VehicleScript.TYPES.has("grosse_moto"), "Type grosse_moto manquant")
	assert("Superbike" in VehicleScript.TYPES["grosse_moto"]["name"] or "Luxe" in VehicleScript.TYPES["grosse_moto"]["name"], "grosse_moto doit être une superbike de luxe")
	assert(VehicleScript.TYPES["grosse_moto"]["speed"] >= 40.0, "Vitesse superbike de luxe doit être >= 40 m/s")
	print("OK: Superbike de luxe validée (%s, %s m/s)" % [VehicleScript.TYPES["grosse_moto"]["name"], VehicleScript.TYPES["grosse_moto"]["speed"]])

	# 2. Vérification de la Concession de Luxe
	assert(Dealership.CATALOG.has("clando"), "Concession doit vendre la berline de luxe")
	assert(Dealership.CATALOG.has("suv"), "Concession doit vendre le SUV de luxe")
	assert(Dealership.CATALOG.has("jakarta"), "Concession doit vendre le T-MAX de luxe")
	assert(Dealership.CATALOG.has("grosse_moto"), "Concession doit vendre la Superbike")
	print("OK: Catalogue Concession de Luxe complet (%d modèles)" % Dealership.CATALOG.size())

	# 3. Vérification de l'Agence de Location de Luxe
	assert(Rental.FLEET.has("clando"), "Location doit proposer la berline VIP")
	assert(Rental.FLEET.has("suv"), "Location doit proposer le SUV V8")
	assert(Rental.FLEET.has("jakarta"), "Location doit proposer le T-MAX")
	assert(Rental.FLEET.has("grosse_moto"), "Location doit proposer la Superbike")
	print("OK: Flotte Agence de Location de Luxe complète (%d modèles)" % Rental.FLEET.size())

	# 4. Instanciation des véhicules de luxe
	var car = VehicleScript.new()
	car.vehicle_type = "clando"
	root.add_child(car)
	assert(car.display_name != "", "Nom affiché du véhicule vide")
	print("OK: Instanciation 3D de la Berline de Luxe réussie : %s" % car.display_name)
	
	var moto = VehicleScript.new()
	moto.vehicle_type = "jakarta"
	root.add_child(moto)
	assert(moto.display_name != "", "Nom affiché du scooter vide")
	print("OK: Instanciation 3D du Maxi-Scooter T-MAX réussie : %s" % moto.display_name)
	
	var superbike = VehicleScript.new()
	superbike.vehicle_type = "grosse_moto"
	root.add_child(superbike)
	assert(superbike.display_name != "", "Nom affiché de la superbike vide")
	print("OK: Instanciation 3D de la Superbike V4 réussie : %s" % superbike.display_name)
	
	var suv = VehicleScript.new()
	suv.vehicle_type = "suv"
	root.add_child(suv)
	assert(suv.display_name != "", "Nom affiché du SUV vide")
	print("OK: Instanciation 3D du SUV de Luxe réussie : %s" % suv.display_name)
	
	print("TOUS LES TESTS DES AUTOS ET MOTOS DE LUXE SONT PASSÉS AVEC SUCCÈS !")
	quit(0)
