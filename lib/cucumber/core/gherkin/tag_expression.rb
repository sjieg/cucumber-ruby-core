module Cucumber
module Core
module Gherkin
  class TagExpression

    attr_reader :limits

    def initialize(tag_expressions)
      @ands = []
      @limits = {}
      tag_expressions.each {|expr| add(expr.strip.split(/\s*,\s*/)) }
    end

    def empty?
      @ands.empty?
    end

    def evaluate(tags)
      return true if @ands.flatten.empty?
      vars = Hash[*tags.map{|tag| [tag.name, true]}.flatten]
      raise "No vars" if vars.nil? # Useless statement to prevent ruby warnings about unused var
      !!Kernel.eval(ruby_expression)
    end

  private

    def add(tags_with_negation_and_limits)
      negatives, positives = tags_with_negation_and_limits.partition{|tag| tag =~ /^~/}
      @ands << (store_and_extract_limits(negatives, true) + store_and_extract_limits(positives, false))
    end

    def store_and_extract_limits(tags_with_negation_and_limits, negated)
      tags_with_negation = []
      tags_with_negation_and_limits.each do |tag_with_negation_and_limit|
        tag_with_negation, limit = tag_with_negation_and_limit.split(':')
        tags_with_negation << tag_with_negation

        next unless limit

        tag_without_negation = without_negation(tag_with_negation, negated)

        raise inconsistent_tag_limits_error_message(tag_without_negation, @limits[tag_without_negation], limit) unless limit_reached?(@limits[tag_without_negation], limit.to_i)

        @limits[tag_without_negation] = limit.to_i
      end
      tags_with_negation
    end

    def inconsistent_tag_limits_error_message(tag, existing_limit, given_limit)
      "Inconsistent tag limits for #{tag}: #{@limits[tag_without_negation]} and #{limit.to_i}"
    end

    def limit_reached?(value, limit)
      !value || value == limit
    end

    def without_negation(tag, negated=nil)
      negated ? tag[1..-1] : tag
    end

    def ruby_expression
      "(" + @ands.map do |ors|
        ors.map do |tag|
          tag =~ /^~(.*)/ ? "!vars['#{$1}']" : "vars['#{tag}']"
        end.join("||")
      end.join(")&&(") + ")"
    end
  end
end
end
end
