require "json"
require "murmurhash3"

require_relative "evaluation"
require_relative "../common/repository"

class Evaluator < Evaluation

  def initialize(repository)

    unless repository.kind_of?(Repository)

      raise "The 'repository' parameter must be of '" + Repository.to_s + "' data type"
    end

    @repository = repository
  end

  def bool_variation(identifier, target, default_value, callback)

    val variation = evaluate(identifier, target, "boolean", callback)

    if variation != nil

      return variation.value == "true"
    end

    default_value
  end

  def string_variation(identifier, target, default_value, callback)

    val variation = evaluate(identifier, target, "string", callback)

    if variation != nil

      return variation.value
    end

    default_value
  end

  def number_variation(identifier, target, default_value, callback)

    val variation = evaluate(identifier, target, "int", callback)

    if variation != nil

      return variation.value.to_i
    end

    default_value
  end

  def json_variation(identifier, target, default_value, callback)

    val variation = evaluate(identifier, target, "json", callback)

    if variation != nil

      return JSON.parse(variation.value)
    end

    default_value
  end

  def evaluate(identifier, target, expected, callback)

    unless callback.kind_of?(FlagEvaluateCallback)

      raise "The 'callback' parameter must be of '" + FlagEvaluateCallback.to_s + "' data type"
    end

    val flag = @repository.get_flag(identifier)

    if flag != nil && flag.kind == expected

      unless flag.prerequisites.empty

        pre_req = check_pre_requisite(flag, target)

        unless pre_req

          return find_variation(flag.variations, flag.off_variation)
        end
      end

      variation = evaluate_flag(flag, target)

      if variation != nil

        if callback != nil

          callback.process_evaluation(flag, target, variation)
        end

        return variation
      end
    end

    nil
  end

  protected

  def get_attr_value(target, attribute)

    if attribute != nil && !attribute.empty?

      if target.respond_to?(:'' + attribute, :include_private)

        puts "The attribute " + attribute.to_s + " exists (1)"

        return target.send(:'' + attribute)
      else

        result = target.attributes.key?(attribute)

        if result == nil

          puts "The attribute " + attribute.to_s + " does not exist"

        else

          puts "The attribute " + attribute.to_s + " exists (2)"
        end

        return result
      end
    end

    puts "The passed attribute is empty"

    nil
  end

  def find_variation(variations, identifier)

    if identifier != nil && !identifier.empty?

      variations.each do |v|

        if v.identifier == identifier

          return v
        end
      end
    end

    nil
  end

  def get_normalized_number(property, bucket_by)

    joined = property.to_s + ":" + bucket_by.to_s
    hash = MurmurHash3::V32.str_hash(joined, joined.length)
    (hash % 100) + 1
  end

  def is_enabled(target, bucket_by, percentage)

    property = get_attr_value(target, bucket_by)

    if property != nil

      bucket_id = get_normalized_number(property, bucket_by)

      return percentage > 0 && bucket_id <= percentage
    end

    false
  end

  def evaluate_distribution(distribution, target)

    if distribution != nil

      variation = ""

      distribution.variations.each do |weighted_variation|

        variation = weighted_variation.variation

        if is_enabled(target, distribution.bucket_by, weighted_variation.weight)

          return variation
        end
      end

      return variation
    end

    nil
  end

  def evaluate_clauses(clauses, target)

    clauses.each do |clause|

      unless evaluate_clause(clause, target)

        return false
      end
    end

    true
  end

  def evaluate_clause(clause, target)

    if clause == nil

      return false
    end

    operator = clause.op

    if operator == nil || operator.empty?

      return false
    end

    attr_value = get_attr_value(target, clause.attribute)

    if attr_value == nil

      return false
    end

    object = attr_value.to_s
    value = clause.values[0]

    if operator == "starts_with"

      return object.start_with?(value)
    end

    if operator == "ends_with"

      return object.end_with?(value)
    end

    if operator == "match"

      match = object.match?(value)
      return match != nil && !match.empty?
    end

    if operator == "contains"

      return object.include?(value)
    end

    if operator == "equal"

      return object.casecmp?(value)
    end

    if operator == "equal_sensitive"

      return object == value
    end

    if operator == "in"

      return object.include?(value)
    end

    if operator == "segmentMatch"

      return is_target_included_or_excluded_in_segment(clause.values, target)
    end

    false
  end

  def is_target_included_or_excluded_in_segment(segment_list, target)

  end

  def evaluate_rules(serving_rules, target) end

  def evaluate_rule(serving_rule, target) end

  def evaluate_variation_map(variation_maps, target) end

  def evaluate_flag(feature_config, target) end

  def check_pre_requisite(parent_feature_config, target) end

  private

  def is_target_in_list(target, list_of_target) end
end