extends Node
class_name ApiHandler

@export var api_base_url: String = "http://localhost:5000"

func post(path:String, data:Dictionary, cb:Callable) -> void:
    var req := HTTPRequest.new()
    add_child(req)
    req.request_completed.connect(cb)
    var headers = ["Content-Type: application/json"]
    var url = "%s%s" % [api_base_url, path]
    req.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(data))

func get(path:String, cb:Callable) -> void:
    var req := HTTPRequest.new()
    add_child(req)
    req.request_completed.connect(cb)
    var url = "%s%s" % [api_base_url, path]
    req.request(url)
