require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/object/inclusion'

module ActiveRecord
  module AttributeMethods
    module TimeZoneConversion
      class Type # :nodoc:
        def initialize(column)
          @column = column
        end

        def type_cast(value)
          value = @column.type_cast(value)
          value.acts_like?(:time) ? value.in_time_zone : value
        end

        def type
          @column.type
        end
      end

      extend ActiveSupport::Concern

      included do
        config_attribute :time_zone_aware_attributes, :global => true
        self.time_zone_aware_attributes = false

        config_attribute :skip_time_zone_conversion_for_attributes
        self.skip_time_zone_conversion_for_attributes = []
      end

      module ClassMethods
        protected
        # The enhanced read method automatically converts the UTC time stored in the database to the time
        # zone stored in Time.zone.
        def attribute_cast_code(attr_name)
          column = columns_hash[attr_name]

          if create_time_zone_conversion_attribute?(attr_name, column)
            typecast             = "v = #{super}"
            time_zone_conversion = "v.acts_like?(:time) ? v.in_time_zone : v"

            "((#{typecast}) && (#{time_zone_conversion}))"
          else
            super
          end
        end

        # Defined for all +datetime+ and +timestamp+ attributes when +time_zone_aware_attributes+ are enabled.
        # This enhanced write method will automatically convert the time passed to it to the zone stored in Time.zone.
        def define_method_attribute=(attr_name)
          if create_time_zone_conversion_attribute?(attr_name, columns_hash[attr_name])
            method_body, line = <<-EOV, __LINE__ + 1
              def #{attr_name}=(original_time)
                time = original_time
                unless time.acts_like?(:time)
                  time = time.is_a?(String) ? Time.zone.parse(time) : time.to_time rescue time
                end
                time = time.in_time_zone rescue nil if time
                changed = read_attribute(:#{attr_name}) != time
                write_attribute(:#{attr_name}, original_time)
                #{attr_name}_will_change! if changed
                @attributes_cache["#{attr_name}"] = time
              end
            EOV
            generated_attribute_methods.module_eval(method_body, __FILE__, line)
          else
            super
          end
        end

        private
        def create_time_zone_conversion_attribute?(name, column)
          time_zone_aware_attributes &&
            !self.skip_time_zone_conversion_for_attributes.include?(name.to_sym) &&
            [:datetime, :timestamp].include?(column.type)
        end
      end
    end
  end
end
