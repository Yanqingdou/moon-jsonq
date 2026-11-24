/// moon-jsonq: filter parser — lexer + recursive-descent parser.
///
/// Grammar (precedence, lowest first):
///   pipe   := comma ('|' comma)*
///   comma  := alt (',' alt)*
///   alt    := or ('//' or)*
///   or     := and ('or' and)*
///   and    := cmp ('and' cmp)*
///   cmp    := add (('=='|'!='|'<'|'<='|'>'|'>=') add)?
///   add    := mul (('+'|'-') mul)*
///   mul    := unary (('*'|'/'|'%') unary)*
///   unary  := '-' unary | postfix
///   postfix:= term ('.' suffix | '?')*
///   term   := '.' suffix* | '(' filter ')' | '[' filter? ']'
///           | '{' object '}' | 'if' … 'end' | literal | builtin-call
///
/// Precedence was checked against jq 1.7, e.g.
/// `.a, .b | .x` is `(.a, .b) | .x`, and
/// `.a // 2 | . + 10` is `(.a // 2) | (. + 10)`.
///
/// Errors use `raise ParseError(msg)` inside the parser and
/// `parse_filter` turns that into `Err(msg)`, so a bad filter
/// never crashes the CLI — it prints `mq: <msg>` and exits 1.
///
/// Not yet parsed (clear `Err`, see docs/PLAN.md):
/// `def`, `reduce`, `group_by`, `test` (regex), `..`,
/// `$variables`, string interpolation `"\(…)"`, `getpath`.

///|
pub(all) suberror ParseError {
  ParseError(String)
}

///|
/// Parse a filter string. Returns `Ok(filter)` or an error
/// message a human can act on.
pub fn parse_filter(text : String) -> Result[Filter, String] {
  try {
    let tokens = tokenize(text)
    let parser = { tokens, pos: 0, }
    let filter = parser.parse_pipe()
    match parser.peek() {
      Eof => Ok(filter)
      _ => Err("unexpected trailing input in filter '" + text + "'")
    }
  } catch {
    ParseError(msg) => Err(msg)
  }
}

// ------------------------------------------------------------------
// Lexer
// ------------------------------------------------------------------

///|
priv enum Token {
  Dot
  Ident(String)
  StrLit(String)
  NumLit(Double)
  Pipe
  Comma
  Colon
  LBracket
  RBracket
  LBrace
  RBrace
  LParen
  RParen
  Plus
  Minus
  Star
  Slash
  Percent
  EqEq
  NotEq
  Lt
  Le
  Gt
  Ge
  Alt
  Question
  Eof
}

///|
priv struct Lexer {
  chars : Array[Char]
  mut pos : Int32
}

///|
fn Lexer::peek(self : Lexer) -> Char? {
  if self.pos < self.chars.length() {
    Some(self.chars[self.pos])
  } else {
    None
  }
}

///|
fn Lexer::peek_at(self : Lexer, n : Int32) -> Char? {
  let i = self.pos + n
  if i < self.chars.length() {
    Some(self.chars[i])
  } else {
    None
  }
}

///|
fn Lexer::advance(self : Lexer) -> Char? {
  let c = self.peek()
  if c is Some(_) {
    self.pos = self.pos + 1
  }
  c
}

///|
fn Lexer::skip_ws(self : Lexer) -> Unit {
  while self.peek() is Some(c) && c.is_ascii_whitespace() {
    ignore(self.advance())
  }
}

///|
fn tokenize(text : String) -> Array[Token] raise ParseError {
  let lexer = { chars: text.to_array(), pos: 0, }
  let tokens : Array[Token] = []
  let mut done = false
  while !done {
    lexer.skip_ws()
    match lexer.peek() {
      None => {
        tokens.push(Eof)
        done = true
      }
      Some(c) =>
        if c.is_ascii_digit() {
          tokens.push(NumLit(lexer.read_number()))
        } else if c == '.' {
          match lexer.peek_at(1) {
            Some(d) if d.is_ascii_digit() =>
              tokens.push(NumLit(lexer.read_number()))
            _ => {
              ignore(lexer.advance())
              tokens.push(Dot)
            }
          }
        } else if c == '"' {
          tokens.push(StrLit(lexer.read_string()))
        } else if c.is_ascii_alphabetic() || c == '_' {
          tokens.push(Ident(lexer.read_ident()))
        } else {
          ignore(lexer.advance())
          match c {
            '|' =>
              if lexer.peek() is Some('|') {
                ignore(lexer.advance())
                tokens.push(Alt)
              } else {
                tokens.push(Pipe)
              }
            ',' => tokens.push(Comma)
            ':' => tokens.push(Colon)
            '[' => tokens.push(LBracket)
            ']' => tokens.push(RBracket)
            '{' => tokens.push(LBrace)
            '}' => tokens.push(RBrace)
            '(' => tokens.push(LParen)
            ')' => tokens.push(RParen)
            '+' => tokens.push(Plus)
            '-' => tokens.push(Minus)
            '*' => tokens.push(Star)
            '/' =>
              if lexer.peek() is Some('/') {
                ignore(lexer.advance())
                tokens.push(Alt)
              } else {
                tokens.push(Slash)
              }
            '%' => tokens.push(Percent)
            '?' => tokens.push(Question)
            '=' =>
              if lexer.peek() is Some('=') {
                ignore(lexer.advance())
                tokens.push(EqEq)
              } else {
                raise ParseError("unexpected '=' — did you mean '=='?")
              }
            '!' =>
              if lexer.peek() is Some('=') {
                ignore(lexer.advance())
                tokens.push(NotEq)
              } else {
                raise ParseError("unexpected '!' — did you mean '!='?")
              }
            '<' =>
              if lexer.peek() is Some('=') {
                ignore(lexer.advance())
                tokens.push(Le)
              } else {
                tokens.push(Lt)
              }
            '>' =>
              if lexer.peek() is Some('=') {
                ignore(lexer.advance())
                tokens.push(Ge)
              } else {
                tokens.push(Gt)
              }
            _ =>
              raise ParseError(
                "unexpected character '" + c.to_string() + "' in filter",
              )
          }
        }
    }
  }
  tokens
}

///|
fn Lexer::read_number(self : Lexer) -> Double raise ParseError {
  let chars : Array[Char] = []
  let mut last : Char = ' '
  while self.peek() is Some(c) &&
        (
          c.is_ascii_digit() ||
          c == '.' ||
          c == 'e' ||
          c == 'E' ||
          ((c == '+' || c == '-') && (last == 'e' || last == 'E'))
        ) {
    chars.push(c)
    last = c
    ignore(self.advance())
  }
  let text = String::from_array(chars)
  @string.parse_double(text) catch {
    _ => raise ParseError("invalid number '" + text + "'")
  }
}

///|
fn Lexer::read_ident(self : Lexer) -> String {
  let chars : Array[Char] = []
  while self.peek() is Some(c) &&
        ((c.is_ascii_alphabetic() || c.is_ascii_digit()) || c == '_') {
    chars.push(c)
    ignore(self.advance())
  }
  String::from_array(chars)
}

///|
fn Lexer::read_string(self : Lexer) -> String raise ParseError {
  // Consume the opening quote.
  ignore(self.advance())
  let chars : Array[Char] = []
  while true {
    match self.advance() {
      None => raise ParseError("unterminated string literal in filter")
      Some('"') => return String::from_array(chars)
      Some('\\') =>
        match self.advance() {
          None => raise ParseError("unterminated string literal in filter")
          Some('n') => chars.push('\n')
          Some('r') => chars.push('\r')
          Some('t') => chars.push('\t')
          Some('b') => chars.push('\u{08}')
          Some('f') => chars.push('\u{0C}')
          Some('/') => chars.push('/')
          Some('\\') => chars.push('\\')
          Some('"') => chars.push('"')
          Some('u') => {
            let mut code = 0
            let mut i = 0
            while i < 4 {
              match self.advance() {
                Some(c) if c.is_ascii_hexdigit() => {
                  let d = if c.is_ascii_digit() {
                    c.to_int() - '0'.to_int()
                  } else if c >= 'a' && c <= 'f' {
                    c.to_int() - 'a'.to_int() + 10
                  } else {
                    c.to_int() - 'A'.to_int() + 10
                  }
                  code = code * 16 + d
                }
                _ => raise ParseError("invalid \\u escape in string literal")
              }
              i = i + 1
            }
            chars.push(code.unsafe_to_char())
          }
          Some('(') =>
            raise ParseError(
              "string interpolation \"\\(...\\)\" is not supported yet (P2)",
            )
          Some(c) =>
            raise ParseError(
              "invalid escape '\\" + c.to_string() + "' in string literal",
            )
        }
      Some(c) => chars.push(c)
    }
  }
  raise ParseError("unterminated string literal in filter")
}

// ------------------------------------------------------------------
// Parser
// ------------------------------------------------------------------

///|
priv struct Parser {
  tokens : Array[Token]
  mut pos : Int32
}

///|
fn Parser::peek(self : Parser) -> Token {
  if self.pos < self.tokens.length() {
    self.tokens[self.pos]
  } else {
    Eof
  }
}

///|
fn Parser::next(self : Parser) -> Token {
  let t = self.peek()
  if self.pos < self.tokens.length() {
    self.pos = self.pos + 1
  }
  t
}

///|
fn Parser::eat(self : Parser, tok : Token) -> Bool {
  // Token has no Eq in general (it carries payloads), so
  // compare by matching the discriminant we care about.
  match (self.peek(), tok) {
    (Pipe, Pipe)
    | (Comma, Comma)
    | (Colon, Colon)
    | (LBracket, LBracket)
    | (RBracket, RBracket)
    | (LBrace, LBrace)
    | (RBrace, RBrace)
    | (LParen, LParen)
    | (RParen, RParen)
    | (Plus, Plus)
    | (Minus, Minus)
    | (Star, Star)
    | (Slash, Slash)
    | (Percent, Percent)
    | (EqEq, EqEq)
    | (NotEq, NotEq)
    | (Lt, Lt)
    | (Le, Le)
    | (Gt, Gt)
    | (Ge, Ge)
    | (Alt, Alt)
    | (Question, Question)
    | (Dot, Dot)
    | (Eof, Eof) => {
      ignore(self.next())
      true
    }
    _ => false
  }
}

///|
fn Parser::expect(
  self : Parser,
  tok : Token,
  what : String,
) -> Unit raise ParseError {
  if !self.eat(tok) {
    raise ParseError("expected " + what + " in filter")
  }
}

///|
fn Parser::parse_pipe(self : Parser) -> Filter raise ParseError {
  let parts : Array[Filter] = [self.parse_comma()]
  while self.eat(Pipe) {
    parts.push(self.parse_comma())
  }
  if parts.length() == 1 {
    parts[0]
  } else {
    Pipe(parts)
  }
}

///|
/// Like `parse_pipe`, but the operands are `parse_alt`,
/// not `parse_comma`. Used for object values `{k: v, …}`,
/// where a top-level `,` separates fields instead of
/// being the comma operator.
fn Parser::parse_pipe_no_comma(self : Parser) -> Filter raise ParseError {
  let parts : Array[Filter] = [self.parse_alt()]
  while self.eat(Pipe) {
    parts.push(self.parse_alt())
  }
  if parts.length() == 1 {
    parts[0]
  } else {
    Pipe(parts)
  }
}

///|
fn Parser::parse_comma(self : Parser) -> Filter raise ParseError {
  let parts : Array[Filter] = [self.parse_alt()]
  while self.eat(Comma) {
    parts.push(self.parse_alt())
  }
  if parts.length() == 1 {
    parts[0]
  } else {
    Comma(parts)
  }
}

///|
fn Parser::parse_alt(self : Parser) -> Filter raise ParseError {
  let mut left = self.parse_or()
  while self.eat(Alt) {
    let right = self.parse_or()
    left = Alt(left, right)
  }
  left
}

///|
fn Parser::parse_or(self : Parser) -> Filter raise ParseError {
  let mut left = self.parse_and()
  while true {
    match self.peek() {
      Ident("or") => {
        ignore(self.next())
        let right = self.parse_and()
        left = BinOp(Or, left, right)
      }
      _ => break
    }
  }
  left
}

///|
fn Parser::parse_and(self : Parser) -> Filter raise ParseError {
  let mut left = self.parse_cmp()
  while true {
    match self.peek() {
      Ident("and") => {
        ignore(self.next())
        let right = self.parse_cmp()
        left = BinOp(And, left, right)
      }
      _ => break
    }
  }
  left
}

///|
fn Parser::parse_cmp(self : Parser) -> Filter raise ParseError {
  let left = self.parse_add()
  match self.peek() {
    EqEq => {
      ignore(self.next())
      BinOp(Eq, left, self.parse_add())
    }
    NotEq => {
      ignore(self.next())
      BinOp(Ne, left, self.parse_add())
    }
    Lt => {
      ignore(self.next())
      BinOp(Lt, left, self.parse_add())
    }
    Le => {
      ignore(self.next())
      BinOp(Le, left, self.parse_add())
    }
    Gt => {
      ignore(self.next())
      BinOp(Gt, left, self.parse_add())
    }
    Ge => {
      ignore(self.next())
      BinOp(Ge, left, self.parse_add())
    }
    _ => left
  }
}

///|
fn Parser::parse_add(self : Parser) -> Filter raise ParseError {
  let mut left = self.parse_mul()
  while true {
    match self.peek() {
      Plus => {
        ignore(self.next())
        left = BinOp(Add, left, self.parse_mul())
      }
      Minus => {
        ignore(self.next())
        left = BinOp(Sub, left, self.parse_mul())
      }
      _ => break
    }
  }
  left
}

///|
fn Parser::parse_mul(self : Parser) -> Filter raise ParseError {
  let mut left = self.parse_unary()
  while true {
    match self.peek() {
      Star => {
        ignore(self.next())
        left = BinOp(Mul, left, self.parse_unary())
      }
      Slash => {
        ignore(self.next())
        left = BinOp(Div, left, self.parse_unary())
      }
      Percent => {
        ignore(self.next())
        left = BinOp(Mod, left, self.parse_unary())
      }
      _ => break
    }
  }
  left
}

///|
fn Parser::parse_unary(self : Parser) -> Filter raise ParseError {
  if self.eat(Minus) {
    Neg(self.parse_unary())
  } else {
    self.parse_postfix()
  }
}

///|
fn Parser::parse_postfix(self : Parser) -> Filter raise ParseError {
  let mut base = self.parse_term()
  while true {
    match self.peek() {
      Dot => {
        let suffix = self.parse_dot_suffix()
        base = Pipe([base, suffix])
      }
      LBracket => {
        ignore(self.next())
        let suffix = self.parse_bracket()
        base = Pipe([base, suffix])
      }
      Question =>
        // `f?` — optional. Our evaluator is lenient already,
        // so `?` is accepted and ignored.
        ignore(self.next())
      _ => break
    }
  }
  base
}

///|
/// Parse one `.suffix` after a term, e.g. `.name`, `.["k"]`,
/// `.[0]`, `.[]`. The leading `.` has already been peeked.
fn Parser::parse_dot_suffix(self : Parser) -> Filter raise ParseError {
  self.expect(Dot, "'.'")
  match self.peek() {
    Ident(_) =>
      match self.next() {
        Ident(name) => {
          ignore(self.eat(Question))
          Field(name)
        }
        _ => raise ParseError("unreachable")
      }
    StrLit(_) =>
      match self.next() {
        StrLit(s) => {
          ignore(self.eat(Question))
          IndexStr(s)
        }
        _ => raise ParseError("unreachable")
      }
    LBracket => {
      ignore(self.next())
      self.parse_bracket()
    }
    Dot =>
      raise ParseError("'..' (recursive descent) is not supported yet (P2)")
    _ => Identity
  }
}

///|
/// Parse a `.` term: `.`, `.name`, `.a.b`, `.[0]`, `.[]`, …
/// Each suffix after the first needs its own `.`; a bare
/// identifier after a field is NOT a suffix (it may be the
/// `and` / `or` operator, or the end of the filter).
fn Parser::parse_dot(self : Parser) -> Filter raise ParseError {
  self.expect(Dot, "'.'")
  if self.peek() is Dot {
    raise ParseError("'..' (recursive descent) is not supported yet (P2)")
  }
  let steps : Array[Filter] = []
  // First suffix, if any.
  match self.peek() {
    Ident(_) | StrLit(_) | LBracket => steps.push(self.parse_dot_first())
    Question => ignore(self.next())
    _ => ()
  }
  while true {
    match self.peek() {
      Dot => steps.push(self.parse_dot_suffix())
      LBracket => {
        ignore(self.next())
        steps.push(self.parse_bracket())
      }
      _ => break
    }
  }
  match steps {
    [] => Identity
    [only] => only
    _ => Pipe(steps)
  }
}

///|
/// Parse the first suffix after a leading `.`:
/// `.name`, `.["k"]`, `.[0]`, `.[]`.
fn Parser::parse_dot_first(self : Parser) -> Filter raise ParseError {
  match self.peek() {
    Ident(_) =>
      match self.next() {
        Ident(name) => {
          ignore(self.eat(Question))
          Field(name)
        }
        _ => raise ParseError("unreachable")
      }
    StrLit(_) =>
      match self.next() {
        StrLit(s) => {
          ignore(self.eat(Question))
          IndexStr(s)
        }
        _ => raise ParseError("unreachable")
      }
    LBracket => {
      ignore(self.next())
      self.parse_bracket()
    }
    _ => raise ParseError("expected a field name, string, or '[' after '.'")
  }
}

///|
/// Parse the inside of `.[ … ]`. The opening `[` was consumed.
/// Handles `.[0]`, `.["k"]`, `.[expr]`, `.[]`, and slices
/// `.[a:b]`, `.[a:]`, `.[:b]` with optional expression bounds.
/// `.[ : ]` with both bounds omitted is a syntax error in jq,
/// so it is an error here too.
fn Parser::parse_bracket(self : Parser) -> Filter raise ParseError {
  if self.eat(RBracket) {
    ignore(self.eat(Question))
    return Iterate
  }
  // Slice with an omitted lower bound: `.[:b]`.
  if self.eat(Colon) {
    let upper = if self.peek() is RBracket {
      None
    } else {
      Some(self.parse_pipe())
    }
    self.expect(RBracket, "']'")
    ignore(self.eat(Question))
    if upper is None {
      raise ParseError("'.[:]' needs at least one slice bound")
    }
    return Slice(None, upper)
  }
  let first = self.parse_pipe()
  if self.eat(Colon) {
    // Slice: `.[a:b]` or `.[a:]`.
    let upper = if self.peek() is RBracket {
      None
    } else {
      Some(self.parse_pipe())
    }
    self.expect(RBracket, "']'")
    ignore(self.eat(Question))
    return Slice(Some(first), upper)
  }
  self.expect(RBracket, "']'")
  ignore(self.eat(Question))
  match first {
    Literal(Num(n)) => Index(n.to_int())
    Literal(Str(s)) => IndexStr(s)
    _ => IndexExpr(first)
  }
}

///|
fn Parser::parse_term(self : Parser) -> Filter raise ParseError {
  match self.peek() {
    Dot => self.parse_dot()
    LParen => {
      ignore(self.next())
      let inner = self.parse_pipe()
      self.expect(RParen, "')'")
      inner
    }
    LBracket => {
      ignore(self.next())
      if self.eat(RBracket) {
        Literal(Arr([]))
      } else {
        let inner = self.parse_pipe()
        self.expect(RBracket, "']'")
        ArrayCons([inner])
      }
    }
    LBrace => self.parse_object()
    NumLit(n) => {
      ignore(self.next())
      Literal(Num(n))
    }
    StrLit(s) => {
      ignore(self.next())
      Literal(Str(s))
    }
    Ident(name) => self.parse_ident(name)
    _ =>
      raise ParseError(
        "unexpected token in filter — expected a filter, a literal, or '.'",
      )
  }
}

///|
fn Parser::parse_object(self : Parser) -> Filter raise ParseError {
  self.expect(LBrace, "'{'")
  let fields : Array[ObjectField] = []
  if self.eat(RBrace) {
    return ObjectCons(fields)
  }
  while true {
    // Key: `"k"` or `ident`, or shorthand `{name}`.
    let key = match self.next() {
      StrLit(s) => s
      Ident(name) => name
      _ => raise ParseError("expected an object key in '{…}'")
    }
    let value = if self.eat(Colon) {
      self.parse_pipe_no_comma()
    } else {
      // Shorthand: `{name}` means `{"name": .name}`.
      Field(key)
    }
    fields.push(ObjectField::new(key, value))
    if self.eat(Comma) {
      continue
    } else {
      break
    }
  }
  self.expect(RBrace, "'}'")
  ObjectCons(fields)
}

///|
fn Parser::parse_ident(self : Parser, name : String) -> Filter raise ParseError {
  ignore(self.next())
  match name {
    "true" => Literal(Bool(true))
    "false" => Literal(Bool(false))
    "null" => Literal(Null)
    "if" => self.parse_if()
    "length" => {
      self.eat_parens()
      Length
    }
    "keys" => {
      self.eat_parens()
      Keys
    }
    "sort" => {
      self.eat_parens()
      Sort
    }
    "unique" => {
      self.eat_parens()
      Unique
    }
    "min" => {
      self.eat_parens()
      Min
    }
    "max" => {
      self.eat_parens()
      Max
    }
    "add" => {
      self.eat_parens()
      Add
    }
    "type" => {
      self.eat_parens()
      Type
    }
    "tostring" => {
      self.eat_parens()
      ToString
    }
    "tonumber" => {
      self.eat_parens()
      ToNumber
    }
    "not" => {
      self.eat_parens()
      Not
    }
    "empty" => {
      self.eat_parens()
      Empty
    }
    "map" => Map(self.parse_call_arg("map"))
    "select" => Select(self.parse_call_arg("select"))
    "sort_by" => SortBy(self.parse_call_arg("sort_by"))
    "def" | "reduce" | "group_by" | "test" | "getpath" | "paths" =>
      raise ParseError(
        "'" + name + "' is not supported yet (P2) — see docs/PLAN.md",
      )
    _ =>
      raise ParseError(
        "unknown function '" +
        name +
        "' — did you mean a field like '." +
        name +
        "'?",
      )
  }
}

///|
/// Consume an optional empty `()` after a zero-argument builtin.
fn Parser::eat_parens(self : Parser) -> Unit raise ParseError {
  if self.eat(LParen) {
    self.expect(RParen, "')'")
  }
}

///|
/// Parse `name(filter)` — one filter argument in parentheses.
fn Parser::parse_call_arg(
  self : Parser,
  name : String,
) -> Filter raise ParseError {
  self.expect(LParen, "'(' after '" + name + "'")
  let arg = self.parse_pipe()
  self.expect(RParen, "')'")
  arg
}

///|
/// `if cond then a elif … else b end`.
/// `elif` is sugar for a nested `if` in the else branch.
fn Parser::parse_if(self : Parser) -> Filter raise ParseError {
  let cond = self.parse_pipe()
  match self.next() {
    Ident("then") => ()
    _ => raise ParseError("expected 'then' after 'if' condition")
  }
  let then_f = self.parse_pipe()
  let else_f = match self.peek() {
    Ident("elif") => {
      ignore(self.next())
      self.parse_if_body()
    }
    Ident("else") => {
      ignore(self.next())
      self.parse_pipe()
    }
    Ident("end") => Literal(Null)
    _ => raise ParseError("expected 'elif', 'else' or 'end' after 'if' branch")
  }
  match self.next() {
    Ident("end") => ()
    _ => raise ParseError("expected 'end' after 'if'")
  }
  If(cond, then_f, else_f)
}

///|
/// Parse an `elif` branch body: condition + `then` + branches,
/// without consuming the final `end` (the caller does that).
/// Implemented by reusing `parse_if` on a synthetic `if`:
/// we already consumed `elif`, so parse cond/then/else here.
fn Parser::parse_if_body(self : Parser) -> Filter raise ParseError {
  let cond = self.parse_pipe()
  match self.next() {
    Ident("then") => ()
    _ => raise ParseError("expected 'then' after 'elif' condition")
  }
  let then_f = self.parse_pipe()
  let else_f = match self.peek() {
    Ident("elif") => {
      ignore(self.next())
      self.parse_if_body()
    }
    Ident("else") => {
      ignore(self.next())
      self.parse_pipe()
    }
    Ident("end") => Literal(Null)
    _ =>
      raise ParseError("expected 'elif', 'else' or 'end' after 'elif' branch")
  }
  If(cond, then_f, else_f)
}
