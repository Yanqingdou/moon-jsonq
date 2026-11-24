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
/// `def`, `group_by`, `test` (regex), `..`,
/// `getpath`.

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
  Var(String)
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
  Semicolon
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
            ';' => tokens.push(Semicolon)
            '$' => tokens.push(Var(lexer.read_var()))
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
/// Read a variable name after `$`: `$x`, `$foo_bar`.
fn Lexer::read_var(self : Lexer) -> String raise ParseError {
  let chars : Array[Char] = []
  while self.peek() is Some(c) &&
        ((c.is_ascii_alphabetic() || c.is_ascii_digit()) || c == '_') {
    chars.push(c)
    ignore(self.advance())
  }
  if chars.length() == 0 {
    raise ParseError("expected a variable name after '$'")
  }
  String::from_array(chars)
}

///|
/// Read a string literal, returning its RAW inner content:
/// escapes are left as written (`\n`, `\"`, `\\`, `\(`, …)
/// and decoded later by `decode_escapes` / `parse_str_lit`.
/// Raw mode matters for interpolation: `"\\(x)"` (escaped
/// backslash + paren) must not become an interpolation,
/// while `"\(x)"` must. The closing quote is found by
/// skipping the character after every backslash — except
/// that a `\(` starts an interpolation, whose whole
/// balanced `\(…)` (nested strings included) is skipped,
/// so a `"` inside it does not end the outer string.
fn Lexer::read_string(self : Lexer) -> String raise ParseError {
  // Consume the opening quote.
  ignore(self.advance())
  let chars : Array[Char] = []
  while true {
    match self.advance() {
      None => raise ParseError("unterminated string literal in filter")
      Some('"') => return String::from_array(chars)
      Some('\\') => {
        chars.push('\\')
        match self.peek() {
          Some('(') => {
            // Interpolation: consume the whole balanced group.
            chars.push('(')
            ignore(self.advance())
            self.read_interp_body(chars)
          }
          _ =>
            match self.advance() {
              None => raise ParseError("unterminated string literal in filter")
              Some(c) => chars.push(c)
            }
        }
      }
      Some(c) => chars.push(c)
    }
  }
  raise ParseError("unterminated string literal in filter")
}

///|
/// Consume the body of a `\(...)` interpolation (the `\(` was
/// already consumed) into `chars`, up to and including the
/// matching `)`. Nested parens and nested strings are skipped.
fn Lexer::read_interp_body(
  self : Lexer,
  chars : Array[Char],
) -> Unit raise ParseError {
  let mut depth = 1
  let mut in_str = false
  while true {
    match self.advance() {
      None => raise ParseError("unterminated string literal in filter")
      Some(c) => {
        chars.push(c)
        if in_str {
          if c == '\\' {
            match self.advance() {
              None => raise ParseError("unterminated string literal in filter")
              Some(d) => chars.push(d)
            }
          } else if c == '"' {
            in_str = false
          }
        } else if c == '"' {
          in_str = true
        } else if c == '(' {
          depth = depth + 1
        } else if c == ')' {
          depth = depth - 1
          if depth == 0 {
            return
          }
        }
      }
    }
  }
}

///|
/// Decode the escapes in a raw string literal (`\n`, `\t`,
/// `\\`, `\"`, `\uXXXX`, …). Used for literal text segments;
/// interpolation markers `\(` are handled by `parse_str_lit`
/// before this runs, so they never reach here.
fn decode_escapes(raw : String) -> String raise ParseError {
  let chars = raw.to_array()
  let out : Array[Char] = []
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '\\' {
      if i + 1 >= chars.length() {
        raise ParseError("unterminated string literal in filter")
      }
      let e = chars[i + 1]
      match e {
        'n' => out.push('\n')
        'r' => out.push('\r')
        't' => out.push('\t')
        'b' => out.push('\u{08}')
        'f' => out.push('\u{0C}')
        '/' => out.push('/')
        '\\' => out.push('\\')
        '"' => out.push('"')
        'u' => {
          if i + 5 >= chars.length() {
            raise ParseError("invalid \\u escape in string literal")
          }
          let mut code = 0
          let mut j = 0
          while j < 4 {
            let h = chars[i + 2 + j]
            if h.is_ascii_hexdigit() {
              let d = if h.is_ascii_digit() {
                h.to_int() - '0'.to_int()
              } else if h >= 'a' && h <= 'f' {
                h.to_int() - 'a'.to_int() + 10
              } else {
                h.to_int() - 'A'.to_int() + 10
              }
              code = code * 16 + d
            } else {
              raise ParseError("invalid \\u escape in string literal")
            }
            j = j + 1
          }
          out.push(code.unsafe_to_char())
          i = i + 4
        }
        _ =>
          raise ParseError(
            "invalid escape '\\" + e.to_string() + "' in string literal",
          )
      }
      i = i + 2
    } else {
      out.push(c)
      i = i + 1
    }
  }
  String::from_array(out)
}

///|
/// Turn a raw string literal into a filter: a plain
/// `Literal(Str)` when there is no interpolation, or an
/// `Interp` when the text contains `\(expr)` parts.
/// Each `\(…)` is matched with its closing `)` (nested
/// parens and nested strings are skipped), and the inner
/// source is parsed as a filter.
fn parse_str_lit(raw : String) -> Filter raise ParseError {
  let chars = raw.to_array()
  let parts : Array[InterpPart] = []
  let mut i = 0
  let mut lit_start = 0
  let mut found = false
  while i < chars.length() {
    // An escaped backslash `\\` is literal text: skip the
    // pair, so the `(` after it is not read as a marker.
    if chars[i] == '\\' && i + 1 < chars.length() && chars[i + 1] == '\\' {
      i = i + 2
    } else if chars[i] == '\\' && i + 1 < chars.length() && chars[i + 1] == '(' {
      // Flush the literal text before this interpolation.
      if i > lit_start {
        parts.push(Text(decode_escapes(String::from_array(chars[lit_start:i]))))
      }
      found = true
      // Find the matching ')', skipping nested strings.
      let mut depth = 1
      let mut j = i + 2
      let mut in_str = false
      let mut closed = false
      while j < chars.length() {
        let c = chars[j]
        if in_str {
          if c == '\\' {
            j = j + 1
          } else if c == '"' {
            in_str = false
          }
        } else if c == '"' {
          in_str = true
        } else if c == '(' {
          depth = depth + 1
        } else if c == ')' {
          depth = depth - 1
          if depth == 0 {
            closed = true
            break
          }
        }
        j = j + 1
      }
      if !closed {
        raise ParseError("unterminated \\(...\\) in string literal")
      }
      let inner = String::from_array(chars[i + 2:j])
      parts.push(Expr(parse_inline_filter(inner)))
      i = j + 1
      lit_start = i
    } else {
      i = i + 1
    }
  }
  if !found {
    return Literal(Str(decode_escapes(raw)))
  }
  if lit_start < chars.length() {
    parts.push(
      Text(decode_escapes(String::from_array(chars[lit_start:chars.length()]))),
    )
  }
  Interp(parts)
}

///|
/// Parse a filter from source text, used for the expression
/// inside `\(...)`. The whole source must be one filter.
fn parse_inline_filter(src : String) -> Filter raise ParseError {
  let tokens = tokenize(src)
  let parser = { tokens, pos: 0, }
  let filter = parser.parse_pipe()
  match parser.peek() {
    Eof => filter
    _ => raise ParseError("unexpected input in \\(...\\)")
  }
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
fn Parser::peek_at(self : Parser, n : Int32) -> Token {
  let i = self.pos + n
  if i < self.tokens.length() {
    self.tokens[i]
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
    | (Semicolon, Semicolon)
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
/// `exp as $x | body`. Binds tighter than `,` (like jq:
/// `.a, .b as $x | $x + 10` is `.a, (.b as $x | $x + 10)`),
/// and the body is a full filter.
fn Parser::parse_as(self : Parser) -> Filter raise ParseError {
  let exp = self.parse_alt()
  match self.peek() {
    Ident("as") => {
      ignore(self.next())
      match self.peek() {
        Var(name) => {
          ignore(self.next())
          self.expect(Pipe, "'|' after 'as $name'")
          let body = self.parse_pipe()
          Bind(exp, name, body)
        }
        LBracket | LBrace =>
          raise ParseError(
            "destructuring 'as [$x, …]' / 'as {…}' is not supported yet",
          )
        _ => raise ParseError("expected '$name' after 'as'")
      }
    }
    _ => exp
  }
}

///|
/// Like `parse_as`, but the body stops at a top-level `,`.
/// Used for object values `{k: v, …}`.
fn Parser::parse_as_no_comma(self : Parser) -> Filter raise ParseError {
  let exp = self.parse_alt()
  match self.peek() {
    Ident("as") => {
      ignore(self.next())
      match self.peek() {
        Var(name) => {
          ignore(self.next())
          self.expect(Pipe, "'|' after 'as $name'")
          let body = self.parse_pipe_no_comma()
          Bind(exp, name, body)
        }
        LBracket | LBrace =>
          raise ParseError(
            "destructuring 'as [$x, …]' / 'as {…}' is not supported yet",
          )
        _ => raise ParseError("expected '$name' after 'as'")
      }
    }
    _ => exp
  }
}

///|
/// Like `parse_pipe`, but the operands are `parse_alt`,
/// not `parse_comma`. Used for object values `{k: v, …}`,
/// where a top-level `,` separates fields instead of
/// being the comma operator.
fn Parser::parse_pipe_no_comma(self : Parser) -> Filter raise ParseError {
  let parts : Array[Filter] = [self.parse_as_no_comma()]
  while self.eat(Pipe) {
    parts.push(self.parse_as_no_comma())
  }
  if parts.length() == 1 {
    parts[0]
  } else {
    Pipe(parts)
  }
}

///|
fn Parser::parse_comma(self : Parser) -> Filter raise ParseError {
  let parts : Array[Filter] = [self.parse_as()]
  while self.eat(Comma) {
    parts.push(self.parse_as())
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
        StrLit(raw) => {
          ignore(self.eat(Question))
          match parse_str_lit(raw) {
            Literal(Str(s)) => IndexStr(s)
            f => IndexExpr(f)
          }
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
  // `. as $x | …` is the identity filter followed by a
  // binding, not the field "as": only treat `as` as a field
  // when it is not followed by `$var |`.
  let is_as_binding = match self.peek() {
    Ident("as") => self.peek_at(1) is Var(_) && self.peek_at(2) is Pipe
    _ => false
  }
  if !is_as_binding {
    match self.peek() {
      Ident(_) | StrLit(_) | LBracket => steps.push(self.parse_dot_first())
      Question => ignore(self.next())
      _ => ()
    }
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
        StrLit(raw) => {
          ignore(self.eat(Question))
          match parse_str_lit(raw) {
            Literal(Str(s)) => IndexStr(s)
            f => IndexExpr(f)
          }
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
    StrLit(raw) => {
      ignore(self.next())
      parse_str_lit(raw)
    }
    Var(name) => {
      ignore(self.next())
      Var(name)
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
    // A quoted key may itself be interpolated: `{"\(.k)": v}`.
    let key_filter = match self.next() {
      StrLit(raw) => parse_str_lit(raw)
      Ident(name) => Literal(Str(name))
      _ => raise ParseError("expected an object key in '{…}'")
    }
    let value = if self.eat(Colon) {
      self.parse_pipe_no_comma()
    } else {
      // Shorthand: `{name}` means `{"name": .name}`.
      match key_filter {
        Literal(Str(name)) => Field(name)
        f => IndexExpr(f)
      }
    }
    fields.push(ObjectField::new(key_filter, value))
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
    "split" => Split(self.parse_call_arg("split"))
    "reduce" => self.parse_reduce()
    "def" | "group_by" | "test" | "getpath" | "paths" =>
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
/// `reduce exp as $x (init; update)`.
/// The `exp` is a term (use parens for anything bigger,
/// like jq: `reduce (.[] , .[]) as $x (…; …)`).
fn Parser::parse_reduce(self : Parser) -> Filter raise ParseError {
  let exp = self.parse_postfix()
  match self.next() {
    Ident("as") => ()
    _ => raise ParseError("expected 'as' after 'reduce' expression")
  }
  let name = match self.next() {
    Var(n) => n
    _ => raise ParseError("expected '$name' after 'reduce … as'")
  }
  self.expect(LParen, "'(' after 'reduce … as $name'")
  let init = self.parse_pipe()
  self.expect(Semicolon, "';' in 'reduce … (init; update)'")
  let update = self.parse_pipe()
  self.expect(RParen, "')' after 'reduce … (init; update)'")
  Reduce(exp, name, init, update)
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
