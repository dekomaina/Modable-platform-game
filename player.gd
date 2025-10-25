@tool
class_name Player
extends CharacterBody2D
## Player with Hedera integration (points → HBAR, redeem bars).

const _PLAYER_ACTIONS = {
    Global.Player.ONE: {
        "jump": "player_1_jump",
        "left": "player_1_left",
        "right": "player_1_right",
    },
    Global.Player.TWO: {
        "jump": "player_2_jump",
        "left": "player_2_left",
        "right": "player_2_right",
    },
}

## Which player controls this character?
@export var player: Global.Player = Global.Player.ONE

## Use this to change the sprite frames of your character.
@export var sprite_frames: SpriteFrames = _initial_sprite_frames:
    set = _set_sprite_frames

## How fast does your character move?
@export_range(0, 1000, 10, "suffix:px/s") var speed: float = 500.0:
    set = _set_speed

## How fast does your character accelerate?
@export_range(0, 5000, 1000, "suffix:px/s²") var acceleration: float = 5000.0

## How high does your character jump?
@export_range(-1000, 1000, 10, "suffix:px/s") var jump_velocity = -880.0

## Jump cut factor (variable jump height control)
@export_range(0, 100, 5, "suffix:%") var jump_cut_factor: float = 20

## Coyote time and jump buffer
@export_range(0, 0.5, 1 / 60.0, "suffix:s") var coyote_time: float = 5.0 / 60.0
@export_range(0, 0.5, 1 / 60.0, "suffix:s") var jump_buffer: float = 5.0 / 60.0

## Can your character jump a second time while still in the air?
@export var double_jump: bool = false

# === Hedera / Web3 exports ===
@export var api_base_url: String = "http://localhost:5000"
@export var hedera_account_id: String = ""           # e.g., 0.0.1234567
@export var points_per_hbar: float = 100.0           # 100 points => 1 HBAR
@export var bars_per_hbar: float = 10.0              # for reference/UI only (server controls actual HBAR_PER_BAR)

# Runtime state
var points: int = 0
var bars: int = 0

# If positive, the player is either on the ground, or left the ground less than this long ago
var coyote_timer: float = 0

# If positive, the player pressed jump this long ago
var jump_buffer_timer: float = 0

# If true, the player is already jumping and can perform a double-jump
var double_jump_armed: bool = false

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var original_position: Vector2

@onready var _sprite: AnimatedSprite2D = %AnimatedSprite2D
@onready var _initial_sprite_frames: SpriteFrames = %AnimatedSprite2D.sprite_frames
@onready var _double_jump_particles: CPUParticles2D = %DoubleJumpParticles

# API helper singletons (optional: you can drop these in the scene tree too)
var _api: ApiHandler
var _wallet: WalletManager

func _set_sprite_frames(new_sprite_frames):
    sprite_frames = new_sprite_frames
    if sprite_frames and is_node_ready():
        _sprite.sprite_frames = sprite_frames

func _set_speed(new_speed):
    speed = new_speed
    if not is_node_ready():
        await ready
    if speed == 0:
        _sprite.speed_scale = 0
    else:
        _sprite.speed_scale = speed / 500

func _ready():
    if Engine.is_editor_hint():
        set_process(false)
        set_physics_process(false)
    else:
        Global.gravity_changed.connect(_on_gravity_changed)
        Global.lives_changed.connect(_on_lives_changed)

    original_position = position
    _set_speed(speed)
    _set_sprite_frames(sprite_frames)

    # Create helpers if not present in the scene
    _api = ApiHandler.new()
    add_child(_api)
    _api.api_base_url = api_base_url

    _wallet = WalletManager.new()
    add_child(_wallet)
    if hedera_account_id != "":
        _wallet.hedera_account_id = hedera_account_id

func _on_gravity_changed(new_gravity):
    gravity = new_gravity

func _jump():
    velocity.y = jump_velocity
    coyote_timer = 0
    jump_buffer_timer = 0
    if double_jump_armed:
        double_jump_armed = false
        _double_jump_particles.emitting = true
    elif double_jump:
        double_jump_armed = true

func stomp():
    double_jump_armed = false
    _jump()

func _player_just_pressed(action):
    if player == Global.Player.BOTH:
        return (
            Input.is_action_just_pressed(_PLAYER_ACTIONS[Global.Player.ONE][action])
            or Input.is_action_just_pressed(_PLAYER_ACTIONS[Global.Player.TWO][action])
        )
    return Input.is_action_just_pressed(_PLAYER_ACTIONS[player][action])

func _player_just_released(action):
    if player == Global.Player.BOTH:
        return (
            Input.is_action_just_released(_PLAYER_ACTIONS[Global.Player.ONE][action])
            or Input.is_action_just_released(_PLAYER_ACTIONS[Global.Player.TWO][action])
        )
    return Input.is_action_just_released(_PLAYER_ACTIONS[player][action])

func _get_player_axis(action_a, action_b):
    if player == Global.Player.BOTH:
        return clamp(
            (
                Input.get_axis(
                    _PLAYER_ACTIONS[Global.Player.ONE][action_a],
                    _PLAYER_ACTIONS[Global.Player.ONE][action_b]
                )
                + Input.get_axis(
                    _PLAYER_ACTIONS[Global.Player.TWO][action_a],
                    _PLAYER_ACTIONS[Global.Player.TWO][action_b]
                )
            ),
            -1,
            1
        )
    return Input.get_axis(_PLAYER_ACTIONS[player][action_a], _PLAYER_ACTIONS[player][action_b])

func _physics_process(delta):
    if Global.lives <= 0:
        return

    # Handle jump
    if is_on_floor():
        coyote_timer = (coyote_time + delta)
        double_jump_armed = false

    if _player_just_pressed("jump"):
        jump_buffer_timer = (jump_buffer + delta)

    if jump_buffer_timer > 0 and (double_jump_armed or coyote_timer > 0):
        _jump()

    # Variable jump height
    if _player_just_released("jump") and velocity.y < 0:
        velocity.y *= (1 - (jump_cut_factor / 100.00))

    # Gravity
    if coyote_timer <= 0:
        velocity.y += gravity * delta

    # Horizontal move
    var direction = _get_player_axis("left", "right")
    if direction:
        velocity.x = move_toward(
            velocity.x,
            sign(direction) * speed,
            abs(direction) * acceleration * delta,
        )
    else:
        velocity.x = move_toward(velocity.x, 0, acceleration * delta)

    # Anim
    if velocity == Vector2.ZERO:
        _sprite.play("idle")
    else:
        if not is_on_floor():
            if velocity.y > 0:
                _sprite.play("jump_down")
            else:
                _sprite.play("jump_up")
        else:
            _sprite.play("walk")
        _sprite.flip_h = velocity.x < 0

    move_and_slide()

    coyote_timer -= delta
    jump_buffer_timer -= delta

# === Game economy helpers ===

func add_points(v:int) -> void:
    points += v
    Global.player_points = points if Engine.has_singleton("Global") else points
    # You can emit a signal here for HUD updates

func add_bars(v:int) -> void:
    bars += v

func convert_points_to_hbar() -> void:
    var acct := _wallet.get_account_id()
    if acct == "":
        push_warning("No Hedera account set")
        return
    if points <= 0:
        push_warning("No points to convert")
        return
    var body := {
        "playerId": "player-1",
        "points": points,
        "wallet": acct,
        "rate": points_per_hbar
    }
    _api.post("/api/convert", body, Callable(self, "_on_convert_done"))

func _on_convert_done(_r:int, code:int, _h:PackedStringArray, body:PackedByteArray) -> void:
    var txt := body.get_string_from_utf8()
    print("convert:", code, txt)
    if code == 200:
        points = 0  # points consumed on success

func redeem_bars_to_hbar(bars_to_redeem:int) -> void:
    var acct := _wallet.get_account_id()
    if acct == "":
        push_warning("No Hedera account set")
        return
    if bars_to_redeem <= 0 or bars_to_redeem > bars:
        push_warning("Invalid bars_to_redeem")
        return
    var body := {"wallet": acct, "bars": bars_to_redeem}
    _api.post("/api/redeem", body, Callable(self, "_on_redeem_done"))

func _on_redeem_done(_r:int, code:int, _h:PackedStringArray, body:PackedByteArray) -> void:
    var txt := body.get_string_from_utf8()
    print("redeem:", code, txt)
    if code == 200:
        var data := JSON.parse_string(txt)
        if typeof(data) == TYPE_DICTIONARY and data.has("barsSpent"):
            bars -= int(data["barsSpent"])

func get_hbar_balance() -> void:
    var acct := _wallet.get_account_id()
    if acct == "":
        push_warning("No Hedera account set")
        return
    _api.get("/api/balance/%s" % acct, Callable(self, "_on_balance_done"))

func _on_balance_done(_r:int, code:int, _h:PackedStringArray, body:PackedByteArray) -> void:
    print("balance:", code, body.get_string_from_utf8())

func reset():
    position = original_position
    velocity = Vector2.ZERO
    coyote_timer = 0
    jump_buffer_timer = 0

func _on_lives_changed():
    if Global.lives > 0:
        reset()
