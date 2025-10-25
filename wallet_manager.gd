extends Node
class_name WalletManager

@export var hedera_account_id: String = ""  # e.g. 0.0.1234567

func get_account_id() -> String:
    return hedera_account_id
