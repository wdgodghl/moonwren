var text = "Aé𐍈"
System.print(text.count)
System.print(text.bytes.count)
System.print(text.indexOf("𐍈"))
System.print(text[1])
System.print(text.codePoints[2])
var invalid = String.fromByte(255)
System.print(invalid.bytes[0])
System.print(invalid.codePoints[0])
