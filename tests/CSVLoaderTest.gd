extends Node

func _ready():
	# Assuming CSVLoader is an autoload named CSVLoader
	var table = aCSVLoader.load_csv("res://data/test_items.csv", "item_id")
	print(table)
	# You should see: {"HP_Potion":{"item_id":"HP_Potion","name":"Health Potion",...}, ...}
