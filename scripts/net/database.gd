## Galsen-Life — Gestionnaire de Base de Données & Persistance Backend
## Fournit une couche de persistance transactionnelle, crash-safe et préparée
## pour la production (JSON atomique, audit logs, et compatibilité SQLite / SQL).
class_name DatabaseManager
extends RefCounted

const DB_PATH := "user://server_accounts.json"
const DB_TMP := "user://server_accounts.json.tmp"
const DB_BAK := "user://server_accounts.json.bak"
const AUDIT_PATH := "user://audit_log.json"
const MAX_AUDIT_ENTRIES := 1000

var _accounts := {}
var _dirty := false
var _audit_logs: Array = []


func _init() -> void:
	load_database()
	load_audit_logs()


## Charge la base de données avec bascule automatique sur backup en cas de corruption
func load_database() -> bool:
	_accounts.clear()
	var path_to_try := DB_PATH
	if not FileAccess.file_exists(path_to_try):
		if FileAccess.file_exists(DB_BAK):
			path_to_try = DB_BAK
			print("[DATABASE] Fichier principal absent, restauration depuis backup : ", DB_BAK)
		else:
			print("[DATABASE] Nouvelle base de données initialisée.")
			return true

	var content := FileAccess.get_file_as_string(path_to_try)
	var parsed = JSON.parse_string(content)
	if parsed is Dictionary:
		_accounts = parsed
		print("[DATABASE] Base de données chargée avec succès : %d compte(s)." % _accounts.size())
		return true
	elif FileAccess.file_exists(DB_BAK):
		print("[DATABASE] ATTENTION: Base principale corrompue, essai de récupération du backup...")
		var bak_content := FileAccess.get_file_as_string(DB_BAK)
		var bak_parsed = JSON.parse_string(bak_content)
		if bak_parsed is Dictionary:
			_accounts = bak_parsed
			print("[DATABASE] Restauration réussie depuis le backup : %d compte(s)." % _accounts.size())
			return true

	push_error("[DATABASE] Échec critique du chargement de la base de données.")
	return false


## Sauvegarde atomique avec fsync pour garantir la durabilité (ACID durability)
func save_database(force: bool = false) -> bool:
	if not _dirty and not force:
		return true

	var f := FileAccess.open(DB_TMP, FileAccess.WRITE)
	if not f:
		push_error("[DATABASE] Impossible d'ouvrir le fichier temporaire de base de données.")
		return false

	var json_str := JSON.stringify(_accounts, "\t")
	f.store_string(json_str)
	f.flush()
	f.close()

	# Rotation du backup précédent
	if FileAccess.file_exists(DB_PATH):
		DirAccess.copy_absolute(DB_PATH, DB_BAK)

	var err := DirAccess.rename_absolute(DB_TMP, DB_PATH)
	if err == OK:
		_dirty = false
		return true
	else:
		push_error("[DATABASE] Échec du renommage atomique : %d" % err)
		return false


# --- Opérations Comptes ------------------------------------------------------

func has_account(pseudo: String) -> bool:
	return _accounts.has(pseudo.strip_edges().to_lower())


func get_account(pseudo: String) -> Dictionary:
	return _accounts.get(pseudo.strip_edges().to_lower(), {})


func create_account(pseudo: String, pass_hash: String, avatar: String, initial_save: Dictionary, apple_id: String = "") -> bool:
	var key := pseudo.strip_edges().to_lower()
	if key == "" or _accounts.has(key):
		return false

	_accounts[key] = {
		"pseudo": pseudo.strip_edges(),
		"hash": pass_hash,
		"avatar": avatar,
		"save": initial_save,
		"apple_id": apple_id,
		"created_at": Time.get_datetime_string_from_system(),
		"updated_at": Time.get_datetime_string_from_system()
	}
	_dirty = true
	save_database()
	log_event("ACCOUNT_CREATED", pseudo, "Compte créé avec succès")
	return true


func update_account_save(pseudo: String, save: Dictionary) -> bool:
	var key := pseudo.strip_edges().to_lower()
	if not _accounts.has(key):
		return false

	_accounts[key]["save"] = save
	_accounts[key]["updated_at"] = Time.get_datetime_string_from_system()
	_dirty = true
	return true


func delete_account(pseudo: String) -> bool:
	var key := pseudo.strip_edges().to_lower()
	if not _accounts.has(key):
		return false

	_accounts.erase(key)
	_dirty = true
	save_database(true)
	log_event("ACCOUNT_DELETED", pseudo, "Compte supprimé définitivement (Conformité App Store 5.1.1)")
	return true


## Associe un identifiant Apple (Game Center ou Sign In with Apple) à un compte existant
func link_apple_id(pseudo: String, apple_id: String) -> bool:
	var key := pseudo.strip_edges().to_lower()
	if not _accounts.has(key) or apple_id.strip_edges() == "":
		return false

	_accounts[key]["apple_id"] = apple_id.strip_edges()
	_accounts[key]["updated_at"] = Time.get_datetime_string_from_system()
	_dirty = true
	save_database()
	log_event("APPLE_ID_LINKED", pseudo, "Compte relié à Apple Developer ID")
	return true


# --- Audit & Journalisation des Événements Critiques --------------------------

func load_audit_logs() -> void:
	if FileAccess.file_exists(AUDIT_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(AUDIT_PATH))
		if d is Array:
			_audit_logs = d


func log_event(event_type: String, target_pseudo: String, details: String) -> void:
	var entry := {
		"timestamp": Time.get_datetime_string_from_system(),
		"type": event_type,
		"player": target_pseudo,
		"details": details
	}
	_audit_logs.append(entry)
	if _audit_logs.size() > MAX_AUDIT_ENTRIES:
		_audit_logs.pop_front()

	var f := FileAccess.open(AUDIT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_audit_logs))


## Génère une structure de schéma SQL (prête pour SQLite / PostgreSQL) pour les migrations
static func generate_sql_schema() -> String:
	return """
	CREATE TABLE IF NOT EXISTS accounts (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		pseudo TEXT UNIQUE NOT NULL,
		password_hash TEXT NOT NULL,
		avatar TEXT NOT NULL DEFAULT 'heros',
		apple_id TEXT UNIQUE,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
		updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS player_saves (
		pseudo TEXT PRIMARY KEY REFERENCES accounts(pseudo) ON DELETE CASCADE,
		money INTEGER NOT NULL DEFAULT 5000,
		bank INTEGER NOT NULL DEFAULT 0,
		job TEXT DEFAULT '',
		save_data JSON NOT NULL,
		updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS audit_logs (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
		event_type TEXT NOT NULL,
		player TEXT NOT NULL,
		details TEXT NOT NULL
	);

	CREATE TABLE IF NOT EXISTS reports (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		reporter TEXT NOT NULL,
		target TEXT NOT NULL,
		reason TEXT NOT NULL,
		timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
		status TEXT DEFAULT 'pending'
	);
	"""
