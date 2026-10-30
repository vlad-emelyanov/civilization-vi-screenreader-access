"""Static check for Civ's typed locals.

The game's Lua enforces `local x:table = ...` at runtime: a later `x = false` makes the whole file fail to load
("set local of type table to boolean"). Only LITERAL right-hand sides are checked (true/false, numbers, strings,
{...}, function), nil is always allowed, so false positives stay near zero.

    check(src) -> [(line, message)]
"""
import re

TYPES = {"number", "string", "boolean", "table", "function"}
KEYWORDS = {"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil",
            "not", "or", "repeat", "return", "then", "true", "until", "while"}
# a literal is a whole expression only if no operator / call / index follows it
CONTINUES = {"+", "-", "*", "/", "%", "^", "..", "==", "~=", "<", ">", "<=", ">=", ".", ":", "[", "(", "{",
             "and", "or"}


def tokenize(src):
    """-> [(kind, text, line)] with kind in name/num/str/sym; comments dropped."""
    toks, i, n, line = [], 0, len(src), 1
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
        elif c.isspace():
            i += 1
        elif src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:i + 40])
            if m:
                end = src.find("]" + m.group(1) + "]", i)
                end = n if end < 0 else end + len(m.group(1)) + 2
                line += src.count("\n", i, end)
                i = end
            else:
                j = src.find("\n", i)
                i = n if j < 0 else j
        elif c in "\"'":
            j = i + 1
            while j < n and src[j] != c and src[j] != "\n":
                j += 2 if src[j] == "\\" else 1
            toks.append(("str", src[i:j + 1], line))
            i = j + 1
        elif c == "[" and re.match(r"\[=*\[", src[i:i + 40]):
            m = re.match(r"\[(=*)\[", src[i:i + 40])
            end = src.find("]" + m.group(1) + "]", i)
            end = n if end < 0 else end + len(m.group(1)) + 2
            toks.append(("str", "[[", line))
            line += src.count("\n", i, end)
            i = end
        elif c.isdigit() or (c == "." and i + 1 < n and src[i + 1].isdigit()):
            m = re.match(r"0[xX][0-9a-fA-F]+|\d*\.?\d+(?:[eE][+-]?\d+)?|\d+\.", src[i:i + 60])
            toks.append(("num", m.group(0), line))
            i += len(m.group(0))
        elif c.isalpha() or c == "_":
            m = re.match(r"\w+", src[i:i + 200])
            toks.append(("name", m.group(0), line))
            i += len(m.group(0))
        else:
            m = re.match(r"\.\.\.|\.\.|==|~=|<=|>=", src[i:i + 3])
            s = m.group(0) if m else c
            toks.append(("sym", s, line))
            i += len(s)
    return toks


def _is(tok, text):
    return tok is not None and tok[0] in ("sym", "name") and tok[1] == text


class _Checker:
    def __init__(self, toks):
        self.t = toks
        self.out = []
        self.scopes = [{}]      # name -> (type or None, decl line)
        self.depths = [0]       # bracket depth per block
        self.skip = set()       # token indexes already consumed as assignment targets

    def at(self, i):
        return self.t[i] if 0 <= i < len(self.t) else None

    def lookup(self, name):
        for s in reversed(self.scopes):
            if name in s:
                return s[name]
        return None

    def open(self):
        self.scopes.append({})
        self.depths.append(0)

    def close(self):
        if len(self.scopes) > 1:
            self.scopes.pop()
            self.depths.pop()

    def typed_name(self, j):
        """Annotation after the name at token j -> type name or None."""
        if _is(self.at(j + 1), ":") and self.at(j + 2) and self.at(j + 2)[0] == "name":
            return self.at(j + 2)[1]
        return None

    def literal_types(self, i):
        """Literal type of each comma-separated expression starting at token i (None = not a plain literal)."""
        res = []
        while True:
            tok = self.at(i)
            lit = None
            if tok is None:
                break
            if tok[0] == "name" and tok[1] in ("true", "false"):
                lit, i = "boolean", i + 1
            elif tok[0] == "num":
                lit, i = "number", i + 1
            elif _is(tok, "-") and self.at(i + 1) and self.at(i + 1)[0] == "num":
                lit, i = "number", i + 2
            elif tok[0] == "str":
                lit, i = "string", i + 1
            elif _is(tok, "{"):
                d, j = 0, i
                while j < len(self.t):
                    if self.t[j][0] == "sym" and self.t[j][1] == "{":
                        d += 1
                    elif self.t[j][0] == "sym" and self.t[j][1] == "}":
                        d -= 1
                        if d == 0:
                            break
                    j += 1
                lit, i = "table", j + 1
            elif tok[0] == "name" and tok[1] == "function":
                res.append("function")
                break  # the rest of the list is not worth tracking
            if lit is not None:
                nxt = self.at(i)
                if nxt is not None and (nxt[1] in CONTINUES and nxt[0] in ("sym", "name") or nxt[0] == "str"):
                    lit = None
            res.append(lit)
            if lit is None:
                break
            if _is(self.at(i), ","):
                i += 1
                continue
            break
        return res

    def assign(self, name, lit, line, binding=None):
        if lit is None:
            return
        b = binding or self.lookup(name)
        if not b or b[0] not in TYPES or b[0] == lit:
            return
        self.out.append((line, "'%s' is declared :%s (line %d) but assigned a %s literal: the game fails to load "
                               "the file (use an untyped local, or keep the type)" % (name, b[0], b[1], lit)))

    def parse_local(self, i):
        """`local [function] a[:t], b[:t] [= exprs]`; returns the next index."""
        line = self.t[i][2]
        j = i + 1
        if _is(self.at(j), "function"):
            if self.at(j + 1) and self.at(j + 1)[0] == "name":
                self.scopes[-1][self.at(j + 1)[1]] = (None, line)
            return j
        names = []
        while self.at(j) and self.at(j)[0] == "name":
            name, typ = self.at(j)[1], self.typed_name(j)
            names.append((name, typ, self.at(j)[2]))
            j += 3 if typ else 1
            if _is(self.at(j), ","):
                j += 1
                continue
            break
        if _is(self.at(j), "="):
            lits = self.literal_types(j + 1)
            for k, (name, typ, ln) in enumerate(names):
                if k < len(lits):
                    self.assign(name, lits[k], ln, (typ, ln))
        for name, typ, ln in names:
            self.scopes[-1][name] = (typ, ln)
        return j

    def parse_assign(self, i):
        """Assignment at statement level: `a, b.c, d = exprs`. True if it was one."""
        j, targets = i, []
        while True:
            tok = self.at(j)
            if not tok or tok[0] != "name" or tok[1] in KEYWORDS:
                return False
            start, j, plain = j, j + 1, True
            while True:
                nxt = self.at(j)
                if _is(nxt, ".") or _is(nxt, ":"):
                    plain, j = False, j + 2
                elif _is(nxt, "["):
                    d, plain = 0, False
                    while self.at(j):
                        if _is(self.at(j), "["):
                            d += 1
                        elif _is(self.at(j), "]"):
                            d -= 1
                            if d == 0:
                                break
                        j += 1
                    j += 1
                else:
                    break
            targets.append((self.t[start], plain, start))
            if _is(self.at(j), ","):
                j += 1
                continue
            break
        if not _is(self.at(j), "="):
            return False
        lits = self.literal_types(j + 1)
        for k, (tok, plain, idx) in enumerate(targets):
            self.skip.add(idx)
            if plain and k < len(lits):
                self.assign(tok[1], lits[k], tok[2])
        return True

    def run(self):
        t = self.t
        i, pending = 0, []   # pending: loop variables to bind when the loop's `do` opens
        while i < len(t):
            kind, text, _ = t[i]
            if kind == "sym":
                if text in ("(", "[", "{"):
                    self.depths[-1] += 1
                elif text in (")", "]", "}"):
                    self.depths[-1] -= 1
                i += 1
                continue
            if kind != "name":
                i += 1
                continue
            prev = t[i - 1] if i else None
            if text == "local":
                i = self.parse_local(i)
                continue
            if text == "function":
                self.open()
                j = i + 1
                while self.at(j) and not _is(self.at(j), "("):
                    j += 1
                j += 1
                while self.at(j) and not _is(self.at(j), ")"):
                    if self.at(j)[0] == "name":
                        self.scopes[-1][self.at(j)[1]] = (self.typed_name(j), self.at(j)[2])
                    j += 1
                i = j + 1
                continue
            if text == "for":
                j, pending = i + 1, []
                while self.at(j) and not (_is(self.at(j), "=") or _is(self.at(j), "in")):
                    if self.at(j)[0] == "name":
                        pending.append((self.at(j)[1], self.typed_name(j), self.at(j)[2]))
                    j += 1
                i = j
                continue
            if text == "do":
                self.open()
                for name, typ, ln in pending:
                    self.scopes[-1][name] = (typ, ln)
                pending = []
            elif text in ("if", "repeat"):
                self.open()
            elif text in ("end", "until"):
                self.close()
            elif (i not in self.skip and self.depths[-1] == 0 and not (_is(prev, ".") or _is(prev, ":"))
                  and text not in KEYWORDS):
                self.parse_assign(i)
            i += 1
        return sorted(self.out)


def check(src):
    return _Checker(_tokenize_ok(src)).run()


def _tokenize_ok(src):
    return tokenize(src)


if __name__ == "__main__":
    import sys
    bad = 0
    for p in sys.argv[1:]:
        with open(p, encoding="utf-8-sig", errors="replace") as fh:
            for ln, msg in check(fh.read()):
                print("%s:%d: %s" % (p, ln, msg))
                bad += 1
    sys.exit(1 if bad else 0)
