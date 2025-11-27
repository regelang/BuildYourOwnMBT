/// Type definitions for the MBT language parser

/// Full TypeKind definition that matches the expected structure in typecheck module
pub(all) enum TypeKind {
  Unit
  Int
  Bool
  Double
  String
  Tuple(Array[TypeKind])
  Array(TypeKind)
  Function(Array[TypeKind], TypeKind)
  Defined(String)
  // Generic enum type with type arguments
  GenericEnum(String, Array[TypeKind])
} derive(Show, Eq)

/// Type definition with kind field
pub(all) struct Type {
  kind: TypeKind
} derive(Show, Eq)

/// Parse type from tokens
pub fn parse_type(tokens: ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]) -> (Type, ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]) {
  parse_type_inner(tokens, 0)
}

/// Helper function to parse types with proper precedence
fn parse_type_inner(tokens: ArrayView[@moonbitlang/MiniMoonbit/lexer.Token], depth: Int) -> (Type, ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]) {
  if tokens.length() == 0 {
    return ({ kind: TypeKind::Unit }, tokens)
  }
  
  match tokens[0].kind {
    // Basic types
    Lower("unit") | Lower("Unit") | Upper("Unit") => ({ kind: TypeKind::Unit }, tokens[1:])
    Lower("int") | Lower("Int") | Upper("Int") => ({ kind: TypeKind::Int }, tokens[1:])
    Lower("bool") | Lower("Bool") | Upper("Bool") => ({ kind: TypeKind::Bool }, tokens[1:])
    Lower("double") | Lower("Double") | Upper("Double") => ({ kind: TypeKind::Double }, tokens[1:])
    Lower("string") | Lower("String") | Upper("String") => ({ kind: TypeKind::String }, tokens[1:])
    
    // Array types: Array[T]
    Lower("array") | Lower("Array") | Upper("Array") => {
      if tokens.length() >= 3 && tokens[1].kind is Bracket('[') {
        // Find the matching closing bracket
        let mut bracket_depth = 1
        let mut i = 2
        
        while i < tokens.length() && bracket_depth > 0 {
          match tokens[i].kind {
            Bracket('[') => bracket_depth += 1
            Bracket(']') => bracket_depth -= 1
            _ => ()
          }
          i += 1
        }
        
        if bracket_depth == 0 {
          // Parse the element type (everything between the brackets)
          let (element_type, _) = parse_type_inner(tokens[2:i-1], depth + 1)
          ({ kind: TypeKind::Array(element_type.kind) }, tokens[i:])
        } else {
          ({ kind: TypeKind::Defined("Array") }, tokens[1:])
        }
      } else {
        ({ kind: TypeKind::Defined("Array") }, tokens[1:])
      }
    }
    
    // Generic user-defined types like List[T]
    Upper(name) => {
      if tokens.length() >= 3 && tokens[1].kind is Bracket('[') {
        // Find the matching closing bracket
        let mut bracket_depth = 1
        let mut i = 2
        
        while i < tokens.length() && bracket_depth > 0 {
          match tokens[i].kind {
            Bracket('[') => bracket_depth += 1
            Bracket(']') => bracket_depth -= 1
            _ => ()
          }
          i += 1
        }
        
        if bracket_depth == 0 {
          // Parse the type arguments
          let (type_args, _) = parse_type_list(tokens[2:i-1], depth + 1)
          ({ kind: TypeKind::GenericEnum(name, type_args) }, tokens[i:])
        } else {
          ({ kind: TypeKind::Defined(name) }, tokens[1:])
        }
      } else {
        ({ kind: TypeKind::Defined(name) }, tokens[1:])
      }
    }
    
    // Tuple types: (T1, T2, ...)
    Bracket('(') => {
      parse_tuple_type(tokens, depth)
    }
    
    // Function types and user-defined types
    Lower(name) => {
      // Check if this might be a function type
      let mut found_arrow = false
      let mut arrow_pos = -1
      
      if tokens.length() >= 4 && tokens[1].kind is Bracket('(') {
        // Look ahead to see if this is a function type
        let mut i = 2
        let mut paren_depth = 1
        
        while i < tokens.length() && paren_depth > 0 {
          match tokens[i].kind {
            Bracket('(') => paren_depth += 1
            Bracket(')') => paren_depth -= 1
            Symbol("->") => {
              if paren_depth == 1 {
                found_arrow = true
                arrow_pos = i
                break
              }
            }
            _ => ()
          }
          i += 1
        }
      }
      
      if found_arrow && arrow_pos > 2 {
        // This is a function type: Name(T1, T2, ...) -> ReturnType
        let (param_types, _) = parse_type_list(tokens[2:arrow_pos], depth + 1)
        let (return_type, final_tokens) = parse_type_inner(tokens[arrow_pos+1:], depth + 1)
        ({ kind: TypeKind::Function(param_types, return_type.kind) }, final_tokens)
      } else {
        // User-defined type
        ({ kind: TypeKind::Defined(name) }, tokens[1:])
      }
    }
    
    // Handle standalone symbols that might be part of complex types
    Symbol("::") => {
      // Handle qualified names like Module::Type
      if tokens.length() >= 2 {
        match tokens[1].kind {
          Upper(name) => ({ kind: TypeKind::Defined("::" + name) }, tokens[2:])
          Lower(name) => ({ kind: TypeKind::Defined("::" + name) }, tokens[2:])
          _ => ({ kind: TypeKind::Defined("::") }, tokens[1:])
        }
      } else {
        ({ kind: TypeKind::Defined("::") }, tokens[1:])
      }
    }
    
    _ => ({ kind: TypeKind::Defined("Unknown") }, tokens[1:])
  }
}

/// Parse tuple types
fn parse_tuple_type(tokens: ArrayView[@moonbitlang/MiniMoonbit/lexer.Token], depth: Int) -> (Type, ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]) {
  if tokens.length() == 0 || not(tokens[0].kind is Bracket('(')) {
    return ({ kind: TypeKind::Unit }, tokens)
  }
  
  // Check for empty tuple ()
  if tokens.length() >= 2 && tokens[1].kind is Bracket(')') {
    // Check if this is part of a function type () -> ReturnType
    if tokens.length() >= 4 && tokens[2].kind is Symbol("->") {
      let (return_type, remaining) = parse_type_inner(tokens[3:], depth + 1)
      ({ kind: TypeKind::Function([], return_type.kind) }, remaining)
    } else {
      ({ kind: TypeKind::Unit }, tokens[2:])
    }
  } else {
    // Parse tuple elements
    let (elements, remaining) = parse_type_list(tokens[1:], depth + 1)
    
    // Check if this is actually a function type
    if remaining.length() >= 2 && remaining[0].kind is Symbol("->") {
      let (return_type, final_tokens) = parse_type_inner(remaining[1:], depth + 1)
      ({ kind: TypeKind::Function(elements, return_type.kind) }, final_tokens)
    } else {
      ({ kind: TypeKind::Tuple(elements) }, remaining)
    }
  }
}

/// Parse a list of types (for tuples and function parameters)
fn parse_type_list(tokens: ArrayView[@moonbitlang/MiniMoonbit/lexer.Token], depth: Int) -> (Array[TypeKind], ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]) {
  let types : Array[TypeKind] = []
  let mut current_tokens = tokens
  
  while current_tokens.length() > 0 {
    match current_tokens[0].kind {
      Bracket(')') => {
        return (types, current_tokens[1:])
      }
      Bracket(']') => {
        return (types, current_tokens[1:])
      }
      Symbol(",") => {
        current_tokens = current_tokens[1:]
        continue
      }
      _ => {
        let (ty, remaining) = parse_type_inner(current_tokens, depth + 1)
        types.push(ty.kind)
        current_tokens = remaining
      }
    }
  }
  
  (types, current_tokens)
}