type stage = Lex | Parse | Tacky | Codegen | Assembly | Executable
type target = OS_X | Linux

(* Control which extra-credit features are enabled (to test the test suite) *)
type extra_credit = Bitwise

let platform = ref OS_X (* default to OS X *)
let extra_credit_flags = ref []
let debug = ref false
