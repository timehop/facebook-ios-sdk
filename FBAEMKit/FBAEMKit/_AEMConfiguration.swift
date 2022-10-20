/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if !os(tvOS)

import Foundation

@objcMembers
@objc(FBAEMConfiguration)
final class _AEMConfiguration: NSObject, NSCopying, NSSecureCoding {

  enum CodingKeys: String, CodingKey {
    case defaultCurrency = "default_currency"
    case cutoffTime = "cutoff_time"
    case conversionValueRules = "conversion_value_rules"
    case validFrom = "valid_from"
    case mode = "config_mode"
    case advertiserID = "advertiser_id"
    case businessID = "business_id"
    case paramRule = "param_rule"
  }

  private(set) var cutoffTime: Int

  /// The UNIX timestamp of configuration's valid date and works as a unqiue identifier of the configuration
  private(set) var validFrom: Int
  private(set) var defaultCurrency: String
  private(set) var mode: String
  private(set) var businessID: String?
  private(set) var matchingRule: _AEMAdvertiserRuleMatching?
  private(set) var conversionValueRules: [_AEMRule]
  private(set) var eventSet: Set<String>
  private(set) var currencySet: Set<String>

  private(set) static var ruleProvider: _AEMAdvertiserRuleProviding?

  static func configure(withRuleProvider ruleProvider: _AEMAdvertiserRuleProviding) {
    self.ruleProvider = ruleProvider
  }

  @objc(initWithJSON:)
  init?(json dict: [String: Any]?) {
    guard let dict = dict else { return nil }

    guard let defaultCurrency = dict[CodingKeys.defaultCurrency.rawValue] as? String,
          let cutoffTime = dict[CodingKeys.cutoffTime.rawValue] as? Int,
          let validFrom = dict[CodingKeys.validFrom.rawValue] as? Int,
          let mode = dict[CodingKeys.mode.rawValue] as? String
    else { return nil }

    let businessID = dict[CodingKeys.advertiserID.rawValue] as? String
    let paramRuleJson = dict[CodingKeys.paramRule.rawValue] as? String
    let matchingRule = _AEMConfiguration.ruleProvider?.createRule(json: paramRuleJson)
    guard let rules = _AEMConfiguration.parseRules(dict[CodingKeys.conversionValueRules.rawValue] as? [[String: Any]]),
          !rules.isEmpty,
          businessID == nil || matchingRule != nil else { return nil }

    self.validFrom = validFrom
    self.cutoffTime = cutoffTime
    self.validFrom = validFrom
    self.businessID = businessID
    self.matchingRule = matchingRule
    self.defaultCurrency = defaultCurrency
    self.mode = mode
    conversionValueRules = rules
    eventSet = _AEMConfiguration.getEventSet(from: conversionValueRules)
    currencySet = _AEMConfiguration.getCurrencySet(from: conversionValueRules)
  }

  private init(
    defaultCurrency: String,
    cutoffTime: Int,
    validFrom: Int,
    mode: String,
    businessID: String?,
    matchingRule: _AEMAdvertiserRuleMatching?,
    conversionValueRules: [_AEMRule]
  ) {
    self.defaultCurrency = defaultCurrency
    self.cutoffTime = cutoffTime
    self.validFrom = validFrom
    self.mode = mode
    self.businessID = businessID
    self.matchingRule = matchingRule
    self.conversionValueRules = conversionValueRules
    eventSet = _AEMConfiguration.getEventSet(from: self.conversionValueRules)
    currencySet = _AEMConfiguration.getCurrencySet(from: self.conversionValueRules)
  }

  static func parseRules(_ rules: [[String: Any]]?) -> [_AEMRule]? {
    guard let rules = rules,
          !rules.isEmpty else { return nil }

    var parsedRules: [_AEMRule] = []
    for ruleEntry in rules {
      guard let rule = _AEMRule(json: ruleEntry) else { return nil }

      parsedRules.append(rule)
    }
    // Sort the rules in descending priority order
    parsedRules.sort { obj1, obj2 in
      obj1.priority > obj2.priority
    }
    return parsedRules
  }

  static func getEventSet(from rules: [_AEMRule]) -> Set<String> {
    var eventSet: Set<String> = []
    for rule in rules {
      for event in rule.events {
        eventSet.insert(event.eventName)
      }
    }
    return eventSet
  }

  static func getCurrencySet(from rules: [_AEMRule]) -> Set<String> {
    var currencySet: Set<String> = []
    for rule in rules {
      for event in rule.events {
        if let currencyValueDict = event.values {
          for currency in currencyValueDict.keys {
            currencySet.insert(currency.uppercased())
          }
        }
      }
    }
    return currencySet
  }

  @objc(isSameValidFrom:businessID:)
  func isSame(validFrom: Int, businessID: String?) -> Bool {
    (validFrom == self.validFrom) && isSameBusinessID(businessID)
  }

  func isSameBusinessID(_ businessID: String?) -> Bool {
    businessID == self.businessID
  }

  // MARK: NSSecureCoding

  func encode(with coder: NSCoder) {
    coder.encode(defaultCurrency, forKey: CodingKeys.defaultCurrency.rawValue)
    coder.encode(cutoffTime, forKey: CodingKeys.cutoffTime.rawValue)
    coder.encode(validFrom, forKey: CodingKeys.validFrom.rawValue)
    coder.encode(mode, forKey: CodingKeys.mode.rawValue)
    coder.encode(businessID, forKey: CodingKeys.businessID.rawValue)
    coder.encode(matchingRule, forKey: CodingKeys.paramRule.rawValue)
    coder.encode(conversionValueRules, forKey: CodingKeys.conversionValueRules.rawValue)
  }

  convenience init?(coder: NSCoder) {
    let defaultCurrency = coder.decodeObject(
      of: NSString.self, forKey: CodingKeys.defaultCurrency.rawValue
    ) as String? ?? ""
    let cutoffTime = coder.decodeInteger(forKey: CodingKeys.cutoffTime.rawValue)
    let validFrom = coder.decodeInteger(forKey: CodingKeys.validFrom.rawValue)
    let mode = coder.decodeObject(
      of: NSString.self,
      forKey: CodingKeys.mode.rawValue
    ) as String? ?? ""
    let businessID = coder.decodeObject(of: NSString.self, forKey: CodingKeys.businessID.rawValue) as String?
    let matchingRule = coder.decodeObject(
      of: [NSArray.self, _AEMAdvertiserMultiEntryRule.self, _AEMAdvertiserSingleEntryRule.self],
      forKey: CodingKeys.paramRule.rawValue
    ) as? _AEMAdvertiserRuleMatching
    guard let rules = coder.decodeObject(
      of: [NSArray.self, _AEMRule.self, _AEMEvent.self],
      forKey: CodingKeys.conversionValueRules.rawValue
    ) as? [_AEMRule] else { return nil }

    self.init(
      defaultCurrency: defaultCurrency,
      cutoffTime: cutoffTime,
      validFrom: validFrom,
      mode: mode,
      businessID: businessID,
      matchingRule: matchingRule,
      conversionValueRules: rules
    )
  }

  static var supportsSecureCoding: Bool { true }

  // MARK: NSCopying

  func copy(with zone: NSZone? = nil) -> Any {
    self
  }
}

#endif
