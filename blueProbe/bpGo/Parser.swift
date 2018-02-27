//
//  Parser.swift
//  blueProbe
//
//  Created by biubiu on 2018/2/26.
//  Copyright © 2018年 biubiublue. All rights reserved.
//

import Foundation
import Curry
import Runes
// MARK: - Parser

typealias Tokens = [Token]

struct Parser<T> {
    var parse: (Tokens) -> Result<(T, Tokens)>
}

// MARK: - Parser Extensions

extension Parser {
    /// 执行parser，只返回结果
    func run(_ tokens: Tokens) -> T? {
        switch self.parse(tokens) {
        case .success(let (result, _)):
            return result
        case .failure(let error):
            #if DEBUG
                print("\(error)")
            #endif
            return nil
        }
    }
    
    /// 将执行结果转换成optional的版本
    var optional: Parser<T?> {
        return self.map { (result) -> T? in
            return result
        }
    }
    
    /// 连续执行该Parser直到输入耗尽为止，将所有的结果放在数组中返回，不会返回错误
    var continuous: Parser<[T]> {
        return Parser<[T]> { (tokens) -> Result<([T], Tokens)> in
            var result = [T]()
            var remainder = tokens
            while remainder.count != 0 {
                switch self.parse(remainder) {
                case .success(let (t, rest)):
                    result.append(t)
                    remainder = rest
                case .failure(let error):
                    #if DEBUG
                        print("fail: \(error), continuous to next")
                    #endif
                    remainder = Array(remainder.dropFirst())
                    continue
                }
            }
            
            return .success((result, remainder))
        }
    }
}

/// 尝试执行Parser，执行结果为可选值，如果成功则包含执行结果，失败也同样返回success，结果为nil，失败时不消耗输入
func trying<T>(_ p: Parser<T>) -> Parser<T?> {
    return Parser<T?> { (tokens) -> Result<(T?, Tokens)> in
        switch p.parse(tokens) {
        case .success(let (result, rest)):
            return .success((result, rest))
        case .failure(_):
            return .success((nil, tokens))
        }
    }
}

/// 创建一个始终返回指定值的的算子，不消耗输入
func pure<T>(_ t: T) -> Parser<T> {
    return Parser(parse: { (tokens) -> Result<(T, Tokens)> in
        return .success((t, tokens))
    })
}

/// 创建一个始终返回错误的parser
func fail<T>(_ error: ParserError = .unknown) -> Parser<T> {
    return Parser(parse: { (tokens) -> Result<(T, Tokens)> in
        return .failure(error)
    })
}

/// 只有当p失败时才返回成功，成功时不消耗输入
func not(_ p: Parser<Token>) -> Parser<Token> {
    return Parser<Token> { (tokens) -> Result<(Token, Tokens)> in
        switch p.parse(tokens) {
        case .success(let (r, _)):
            return .failure(.missMatch("Unexpected found: \(r)"))
        case .failure(_):
            return .success((Token(type: .unknown, text: ""), tokens))
        }
    }
}

/// 创建解析单个token并消耗输入, 失败时不消耗输入
func token(_ t: TokenType) -> Parser<Token> {
    return Parser(parse: { (tokens) -> Result<(Token, Tokens)> in
        guard let first = tokens.first, first.type == t else {
            let msg = "Expected type: \(t), found: \(tokens.first?.description ?? "empty")"
            return .failure(.missMatch(msg))
        }
        #if DEBUG
            print("match token: \(first)")
        #endif
        return .success((first, Array(tokens.dropFirst())))
    })
}

// MARK: - Any Tokens

/// 匹配任意一个Token
var anyToken: Parser<Token> {
    return Parser { (tokens) -> Result<(Token, Tokens)> in
        guard let first = tokens.first else {
            return .failure(.custom("tokens empty"))
        }
        return .success((first, Array(tokens.dropFirst())))
    }
}

/// 匹配任意Token类型的Parser直到条件为false，该Parser不会返回错误
func anyTokens(until: @escaping (Token) -> Bool) -> Parser<[Token]> {
    return Parser<[Token]> { (tokens) -> Result<([Token], Tokens)> in
        var result = [Token]()
        var remainder = tokens
        for token in remainder {
            if until(token) {
                break
            }
            result.append(token)
            _ = remainder.removeFirst()
        }
        return .success((result, remainder))
    }
}

/// 获取任意Token知道p成功为止, p不会消耗输入，该方法不会返回错误
func anyTokens(until p: Parser<Token>) -> Parser<[Token]> {
    return (not(p) *> anyToken).many <|> pure([])
}

/// 匹配在l和r之间的任意Token，l和r也会被消耗掉，l和r会出现在结果中，lr匹配失败时会返回错误
func anyTokens(encloseBy l: Parser<Token>, and r: Parser<Token>) -> Parser<[Token]> {
    let content = lookAhead(l) *> lazy(anyTokens(encloseBy: l, and: r)) // 递归匹配
        <|> ({ [$0] } <^> (not(r) *> anyToken)) // 匹配任意token直到碰到r
    
    return curry({ [$0] + Array($1.joined()) + [$2] })
        <^> l
        <*> (content.many <|> pure([])) // many为空的时候会失败
        <*> r
}

/// 匹配在l和r之间的任意Token，l和r会被消耗掉，但不会出现在结果中，lr匹配失败时会返回错误
func anyTokens(inside l: Parser<Token>, and r: Parser<Token>) -> Parser<[Token]> {
    return anyTokens(encloseBy: l, and: r).map {
        Array($0.dropFirst().dropLast()) // 去掉首尾的元素
    }
}

/// 任意被包围在{}、[]、()或<>中的符号
var anyEnclosedTokens: Parser<[Token]> {
    return anyTokens(encloseBy: token(.leftBrace), and: token(.rightBrace)) // {..}
        <|> anyTokens(encloseBy: token(.leftSquare), and: token(.rightSquare)) // [..]
        <|> anyTokens(encloseBy: token(.leftParen), and: token(.rightParen)) // (..)
        <|> anyTokens(encloseBy: token(.leftAngle), and: token(.rightAngle)) // <..>
}

/// 匹配任意字符直到p失败为止，p只有在不被{}、[]、()或<>包围时进行判断
func anyOpenTokens(until p: Parser<Token>) -> Parser<[Token]> {
    return { $0.flatMap {$0} }
        <^> (not(p) *> (anyEnclosedTokens <|> anyToken.map { [$0] })).many
        <|> pure([])
}

// MARK: -

///
func lazy<T>(_ parser: @autoclosure @escaping () -> Parser<T>) -> Parser<T> {
    return Parser<T> { parser().parse($0) }
}

/// 尝试列表中的每一个parser，直到有一个成功为止，如果全部失败则返回一个错误
func choice<T>(_ parsers: [Parser<T>]) -> Parser<T> {
    return Parser<T> { (tokens) -> Result<(T, Tokens)> in
        for parser in parsers {
            if case .success(let (r, rest)) = parser.parse(tokens) {
                return .success((r, rest))
            }
        }
        return .failure(.custom("None parser success!"))
    }
}

/// 执行parser，解析成功时不消耗输入
func lookAhead<T>(_ parser: Parser<T>) -> Parser<T> {
    return Parser<T> { (tokens) -> Result<(T, Tokens)> in
        switch parser.parse(tokens) {
        case .success(let (r, _)):
            return .success((r, tokens))
        case .failure(let error):
            return .failure(error)
        }
    }
}
