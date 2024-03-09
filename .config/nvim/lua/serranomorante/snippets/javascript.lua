---@diagnostic disable: undefined-global
return {
  s(
    "ra_form_print",
    fmt(
      [[
	  <FormDataConsumer>
	    {{({{ {} }}) => (
          <pre>
            <code>{{JSON.stringify({}, null, 2)}}</code>
          </pre>
        )
      }}
	  </FormDataConsumer>
	]],
      { i(1, "formData"), rep(1) }
    )
  ),
}
