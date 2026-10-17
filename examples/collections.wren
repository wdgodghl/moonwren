var inventory = {
  "apples": 3,
  "pears": 2
}

inventory["apples"] = inventory["apples"] + 2
inventory["oranges"] = 4

var counts = [
  inventory["apples"],
  inventory["pears"],
  inventory["oranges"]
]

counts.insert(1, 1)
counts.removeAt(2)

var total = 0
for (count in counts) {
  total = total + count
}

System.print(inventory)
System.print(counts)
System.print(total)
