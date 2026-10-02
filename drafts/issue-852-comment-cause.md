A correction to the cause given above. TensorFlow does not count traces by memory address: it counts them per Python code object.

https://github.com/tensorflow/tensorflow/blob/v2.21.0/tensorflow/python/eager/polymorphic_function/polymorphic_function.py#L551-L572

Every function greta traces is an R function that reticulate wraps in the same Python closure, `wrap_fn.<locals>.fn`, so all of them share one counter. The first trace of each new model's functions counts as a retrace of that one function. Five within ten calls prints the warning, and TensorFlow prints at most two per counter per session, which is why it appears only early in a session:

https://github.com/tensorflow/tensorflow/blob/v2.21.0/tensorflow/python/eager/polymorphic_function/polymorphic_function.py#L110-L112

Sampling ten small models in a loop gives four warnings on the first loop of every fresh session, on main and on #843 alike. They name the log-density and trace-values functions of the fifth and sixth models, each traced once. #843 cannot remove these; the filter proposed here would.
