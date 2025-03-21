module LookupKeysHelper
  def remove_child_link(name, f, opts = {})
    opts[:class] = [opts[:class], "remove_nested_fields"].compact.join(" ")
    f.hidden_field(opts[:method]||:_destroy) + link_to_function(name, "remove_child_node(this);", opts)
  end

  def delete_child_link(name, f, opts = {})
    opts[:class] = [opts[:class], "remove_nested_fields"].compact.join(" ")
    link_to_function(name, "delete_child_node(this);", opts)
  end

  def add_child_link(name, association, opts = {})
    opts[:class] = [opts[:class], "add_nested_fields btn btn-primary"].compact.join(" ")
    opts[:"data-association"] = association
    link_to_function(name.to_s, "add_child_node(this);", opts)
  end

  def show_puppet_class(f)
    # In case of a new smart-var inside a puppetclass (REST nesting only), or a class parameter:
    # Show the parent puppetclass as a context, but permit no change.
    if params["puppetclass_id"]
      select_f f, :puppetclass_id, [Puppetclass.find(params["puppetclass_id"])], :id, :to_label, {}, {:label => _("Puppet class"), :disabled => true}
    elsif f.object.puppet? && f.object.param_class
      text_f(f, :puppetclass_id, :label => _('Puppet Class'), :value => f.object.param_class, :disabled => true)
    else # new smart-var with no particular context
         # Give a select for choosing the parent puppetclass
      select_f(f, :puppetclass_id, Puppetclass.all, :id, :to_label, { :include_blank => _('None') }, {:label => _("Puppet class")})
    end unless @puppetclass # nested smart-vars form in a tab of puppetclass/_form: no edition allowed, and the puppetclass is already visible as a context
  end

  def param_type_selector(f, options = {})
    selectable_f f, :key_type, options_for_select(LookupKey::KEY_TYPES.map { |e| [_(e),e] }, f.object.key_type),{},
                 options.merge({ :disabled => (f.object.puppet? && !f.object.override), :size => "col-md-8", :class=> "without_select2",
                 :help_inline => popover("",_("<dl>" +
               "<dt>String</dt> <dd>Everything is taken as a string.</dd>" +
               "<dt>Boolean</dt> <dd>Common representation of boolean values are accepted.</dd>" +
               "<dt>Integer</dt> <dd>Integer numbers only, can be negative.</dd>" +
               "<dt>Real</dt> <dd>Accept any numerical input.</dd>" +
               "<dt>Array</dt> <dd>A valid JSON or YAML input, that must evaluate to an array.</dd>" +
               "<dt>Hash</dt> <dd>A valid JSON or YAML input, that must evaluate to an object/map/dict/hash.</dd>" +
               "<dt>YAML</dt> <dd>Any valid YAML input.</dd>" +
               "<dt>JSON</dt> <dd>Any valid JSON input.</dd>" +
               "</dl>"), :title => _("How values are validated")).html_safe})
  end

  def validator_type_selector(f)
    selectable_f f, :validator_type, options_for_select(LookupKey::VALIDATOR_TYPES.map { |e| [_(e),e]  }, f.object.validator_type),{:include_blank => _("None")},
               { :disabled => (f.object.puppet? && !f.object.override), :size => "col-md-8", :class=> "without_select2",
                 :onchange => 'validatorTypeSelected(this)',
                 :help_inline => popover("",_("<dl>" +
               "<dt>List</dt> <dd>A list of the allowed values, specified in the Validator rule field.</dd>" +
               "<dt>Regexp</dt> <dd>Validates the input with the regular expression in the Validator rule field.</dd>" +
               "</dl>"), :title => _("Validation types")).html_safe}
  end

  def overridable_lookup_keys(klass, obj)
    klass.class_params.override.where(:environment_classes => {:environment_id => obj.environment}) + klass.lookup_keys
  end

  def can_edit_params?
    authorized_via_my_scope("host_editing", "edit_params")
  end

  def lookup_key_with_diagnostic(obj, lookup_key, lookup_value)
    value, matcher = value_matcher(obj, lookup_key)
    inherited_value = lookup_key.value_before_type_cast(value)
    effective_value = lookup_value.lookup_key_id.nil? ?  inherited_value.to_s : lookup_value.value_before_type_cast.to_s
    warnings  = lookup_key_warnings(lookup_key.required, effective_value.present?)
    popover_value = lookup_key.hidden_value? ? lookup_key.hidden_value : inherited_value

    parameter_value_content(
      "#{parameters_receiver}_lookup_values_attributes_#{lookup_key.id}_value",
      effective_value,
      :popover => diagnostic_popover(lookup_key, matcher, popover_value, warnings),
      :name => "#{lookup_value_name_prefix(lookup_key.id)}[value]",
      :disabled => !lookup_key.overridden?(obj) || lookup_value.use_puppet_default || !can_edit_params?,
      :inherited_value => inherited_value,
      :lookup_key => lookup_key,
      :lookup_key_hidden_value? => lookup_key.hidden_value?,
      :lookup_key_type => lookup_key.key_type)
  end

  def value_matcher(obj, lookup_key)
    if parameters_receiver == "host"
      value = value_hash_cache(obj)[lookup_key.id]
      value_for_key = value.try(:[], lookup_key.key)
      if value_for_key.present?
        [value_for_key[:value], "#{value_for_key[:element]} (#{value_for_key[:element_name]})"]
      else
        [lookup_key.default_value, _("Default value")]
      end
    else #hostgroup
      obj.inherited_lookup_value(lookup_key)
    end
  end

  def diagnostic_popover(lookup_key, matcher, inherited_value, warnings)
    description = lookup_key_description(lookup_key, matcher, inherited_value)
    popover('', description.prepend(warnings[:text]),
            :data => { :placement => 'top' },
            :title => _("Original value info"),
            :icon => warnings[:icon])
  end

  def lookup_key_description(lookup_key, matcher, inherited_value)
    _("<b>Description:</b> %{desc}<br/>
     <b>Type:</b> %{type}<br/>
     <b>Matcher:</b> %{matcher}<br/>
     <b>Inherited value:</b> %{inherited_value}") %
    { :desc => html_escape(lookup_key.description), :type => lookup_key.key_type,
      :matcher => html_escape(matcher), :inherited_value => html_escape(inherited_value) }
  end

  def lookup_key_warnings(required, has_value)
    return { :text => '', :icon => 'info' } if has_value

    if required
      { :text => _("Required parameter without value.<br/><b>Please override!</b><br/>"),
        :icon => "error-circle-o" }
    else
      { :text => _("Optional parameter without value.<br/><i>Will not be sent to Puppet.</i><br/>"),
        :icon => "warning-triangle-o" }
    end
  end

  def override_toggle(overridden)
    return unless can_edit_params?
    link_to_function(icon_text('pencil-square-o', '', :kind => 'fa'), "override_class_param(this)",
                     :title => _("Override this value"),
                     :'data-tag' => 'override',
                     :class =>"btn btn-default btn-md btn-override #{'hide' if overridden}") +
      link_to_function(icon_text('times', '', :kind => 'fa'), "override_class_param(this)",
                       :title => _("Remove this override"),
                      :'data-tag' => 'remove',
                      :class =>"btn btn-default btn-md btn-override #{'hide' unless overridden}")
  end

  def hidden_toggle(hidden, hide_icon = 'eye-slash', unhide_icon = 'eye', strikethrough = false)
    return unless can_edit_params?
    if strikethrough && !hidden
      link_to_function(icon_text(hide_icon, '', :kind => 'fa'), "", :class =>"btn btn-default btn-md btn-hide", :disabled => "disabled", :rel => "twipsy", :title => _("This value is not hidden"))
    else
      link_to_function(icon_text(unhide_icon, '', :kind => 'fa'), "input_group_hidden(this)",
                       :title => _("Unhide this value"),
                       :class =>"btn btn-default btn-md btn-hide #{'hide' unless hidden}") +
          link_to_function(icon_text(hide_icon, "", :class => "#{'btn-strike' if strikethrough}", :kind => 'fa'), "input_group_hidden(this)",
                           :title => _("Hide this value"),
                           :class =>"btn btn-default btn-md btn-hide #{'hide' if hidden}")
    end
  end

  def lookup_value(host_or_hostgroup, lookup_key)
    lookup_key.overridden_value(host_or_hostgroup) || LookupValue.new
  end

  def use_puppet_default_check_box(lookup_key, lookup_value, disabled)
    return unless lookup_key.type == "PuppetclassLookupKey"
    check_box(lookup_value_name_prefix(lookup_key.id), :use_puppet_default,
              :value    => lookup_value.id,
              :disabled => disabled || !can_edit_params?,
              :onchange => "toggleUsePuppetDefaultValue(this, 'value')",
              :hidden   => disabled,
              :title    => _('Use Puppet default'),
              :checked  => lookup_value.use_puppet_default)
  end

  def hidden_lookup_value_fields(lookup_key, lookup_value, disabled)
    return unless can_edit_params?
    value_prefix = lookup_value_name_prefix(lookup_key.id)
    hidden_field(value_prefix, :lookup_key_id, :value => lookup_key.id,
                 :disabled => disabled, :class => 'send_to_remove') +
      hidden_field(value_prefix, :id, :value => lookup_value.id,
                   :disabled => disabled, :class => 'send_to_remove') +
      hidden_field(value_prefix, :_destroy, :value => false,
                   :disabled => disabled, :class => 'send_to_remove destroy')
  end

  # Input tags used to override lookup keys need a 'name' HTML attribute to
  # tell Rails which lookup_value they belong to.
  # This method returns the name attribute for any combination of lookup_key
  # and host/hostgroup. Other objects that may receive parameters too will need
  # to override this method in their respective helpers.
  def lookup_value_name_prefix(lookup_key_id)
    "#{parameters_receiver}[lookup_values_attributes][#{lookup_key_id}]"
  end

  def parameters_receiver
    return 'host' if params.has_key?(:host) || params[:controller] == 'hosts'
    'hostgroup'
  end
end
