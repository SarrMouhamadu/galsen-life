extends Node
## Publicités AdMob : uniquement des vidéos « avec récompense », que le joueur choisit de regarder
## (application « Bonus » du téléphone). Jamais de pub imposée ni de bannière.
## Android : rien n'est chargé au lancement (mémoire des petits téléphones) ; à la première ouverture de
## l'application Bonus : consentement RGPD (formulaire Google UMP), initialisation, puis une vidéo reste préchargée.
## PC lancé depuis l'éditeur : le module fournit une fausse vidéo (8 s) pour tester ; export PC : pas de pub.
## Identifiants : vrai bloc d'annonces dans les versions publiées, bloc de test de Google dans les versions
## de débogage (pas de vraies annonces pendant les essais) ; l'identifiant d'application se règle dans
## project.godot (admob/general/android/app_id).

signal changed ## vidéo prête / plus prête, compteur du jour

const TEST_REWARDED_ID := "ca-app-pub-3940256099942544/5224354917"
const REWARDED_ID := "ca-app-pub-5682888880996180/3210362438" ## bloc d'annonces « Bonus video » du compte AdMob
const REWARD := 2000 ## FCFA par vidéo regardée jusqu'au bout
const COOLDOWN := 240.0 ## secondes entre deux vidéos
const DAILY_MAX := 10 ## vidéos récompensées par jour (date réelle)
const STATE_PATH := "user://pubs.cfg"

var available := false ## le module natif est présent (Android, ou éditeur avec sa simulation)
var _started := false
var _sdk_ready := false ## initialisation du SDK terminée : charger une vidéo avant plantait certains téléphones
var _init_wait := 0.0
var _consenting := false
var _ad: RewardedAd
var _loading := false
var _retry := 0.0
var _cooldown := 0.0
var _today := ""
var _count := 0
var _muted_before := false
var _on_reward := Callable()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_state()
	available = OS.get_name() == "Android" or OS.has_feature("editor")
	if not available or "--no-ads" in OS.get_cmdline_user_args():
		available = false


## Démarre AdMob (première ouverture de l'application Bonus)
func start() -> void:
	if not available or _consenting or _started:
		return
	if OS.get_name() == "Android":
		_consenting = true
		_request_consent()
	else:
		_initialize()


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
		if _cooldown <= 0.0:
			changed.emit()
	if _started and not _sdk_ready:
		# Secours si le SDK ne signale jamais la fin de son initialisation
		_init_wait -= delta
		if _init_wait <= 0.0:
			_on_sdk_ready()
		return
	if _started and _ad == null and not _loading:
		_retry -= delta
		if _retry <= 0.0:
			_load()


## Une vidéo peut être lancée maintenant
func can_show() -> bool:
	_roll_day()
	return _ad != null and _cooldown <= 0.0 and _count < DAILY_MAX


## Pourquoi on ne peut pas (texte pour le téléphone), "" si tout va bien
func why_not() -> String:
	_roll_day()
	if not available:
		return "Les vidéos bonus sont disponibles sur la version téléphone."
	if _count >= DAILY_MAX:
		return "Tu as regardé tes %d vidéos du jour. Reviens demain !" % DAILY_MAX
	if _cooldown > 0.0:
		return "Prochaine vidéo dans %d:%02d." % [int(_cooldown) / 60, int(_cooldown) % 60]
	if _ad == null:
		return "Chargement de la vidéo… (connexion Internet nécessaire)"
	return ""


func left_today() -> int:
	_roll_day()
	return DAILY_MAX - _count


## Lance la vidéo ; on_reward est appelé seulement si elle a été regardée jusqu'au bout
func show_rewarded(on_reward: Callable) -> void:
	if not can_show():
		return
	_on_reward = on_reward
	var ad := _ad
	_ad = null
	var cb := FullScreenContentCallback.new()
	cb.on_ad_dismissed_full_screen_content = func() -> void:
		_restore_sound()
		ad.destroy()
		changed.emit()
	cb.on_ad_failed_to_show_full_screen_content = func(_e: AdError) -> void:
		_restore_sound()
		ad.destroy()
		GameState.notify.emit("La vidéo n'a pas pu s'afficher. Réessaie dans un instant.")
		changed.emit()
	ad.full_screen_content_callback = cb
	var listener := OnUserEarnedRewardListener.new()
	listener.on_user_earned_reward = func(_item: RewardedItem) -> void:
		_count += 1
		_cooldown = COOLDOWN
		_save_state()
		if _on_reward.is_valid():
			_on_reward.call()
	_muted_before = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	ad.show(listener)
	changed.emit()


## RGPD : bouton « Choix de confidentialité » à proposer quand Google l'exige (joueurs européens)
func privacy_options_required() -> bool:
	return OS.get_name() == "Android" and _started and UserMessagingPlatform.consent_information.get_privacy_options_requirement_status() \
		== ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED


func show_privacy_options() -> void:
	UserMessagingPlatform.show_privacy_options_form(func(_e: FormError) -> void: changed.emit())


func _request_consent() -> void:
	var params := ConsentRequestParameters.new()
	UserMessagingPlatform.consent_information.update(params, func() -> void:
		if UserMessagingPlatform.consent_information.get_consent_status() == ConsentInformation.ConsentStatus.REQUIRED \
				and UserMessagingPlatform.consent_information.get_is_consent_form_available():
			UserMessagingPlatform.load_consent_form(func(form: ConsentForm) -> void:
				form.show(func(_e: FormError) -> void: _initialize()),
				func(_e: FormError) -> void: _initialize())
		else:
			_initialize(),
		func(_e: FormError) -> void: _initialize())


func _initialize() -> void:
	if _started:
		return
	_started = true
	var config := RequestConfiguration.new()
	config.max_ad_content_rating = RequestConfiguration.MAX_AD_CONTENT_RATING_T # jeu classé 12+ : pas de pub pour adultes
	MobileAds.set_request_configuration(config)
	_init_wait = 20.0
	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = func(_status: InitializationStatus) -> void:
		_on_sdk_ready.call_deferred()
	MobileAds.initialize(listener)


func _on_sdk_ready() -> void:
	if _sdk_ready:
		return
	_sdk_ready = true
	_load()


func _load() -> void:
	if not _sdk_ready or _loading:
		return
	_loading = true
	var cb := RewardedAdLoadCallback.new()
	cb.on_ad_loaded = func(ad: RewardedAd) -> void:
		_loading = false
		_ad = ad
		changed.emit()
	cb.on_ad_failed_to_load = func(_e: LoadAdError) -> void:
		_loading = false
		_retry = 60.0
	RewardedAdLoader.new().load(TEST_REWARDED_ID if OS.is_debug_build() else REWARDED_ID, AdRequest.new(), cb)


func _restore_sound() -> void:
	AudioServer.set_bus_mute(0, _muted_before)


func _roll_day() -> void:
	var d := Time.get_date_string_from_system()
	if d != _today:
		_today = d
		_count = 0


func _load_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(STATE_PATH) == OK:
		_today = cfg.get_value("pubs", "jour", "")
		_count = cfg.get_value("pubs", "vues", 0)
	_roll_day()


func _save_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("pubs", "jour", _today)
	cfg.set_value("pubs", "vues", _count)
	cfg.save(STATE_PATH)
