var total = 0

for (item in 1..10) {
  if (item % 2 == 0) continue
  if (item > 7) break
  total = total + item
}

System.print(total)
