var readings = [8, 3, 5, 2, 7, 4]
readings.sort()

var normalized = readings.where(Fn.new { |value| value % 2 == 0 }).map(Fn.new { |value| value * 10 })

System.print(normalized.toList)
System.print(normalized.reduce(0, Fn.new { |total, value| total + value }))
System.print(normalized.join(" + "))

var labels = {"runtime": "MoonWren", "language": "MoonBit"}
for (entry in labels) {
  System.print(entry.key + ": " + entry.value)
}

System.print("  reusable core  ".trim().replace("core", "library"))
System.print((1..Num.infinity).any(Fn.new { |value| value == 3 }))
