package io.ente.ensu.chat;

import com.agog.mathdisplay.MTMathView;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

final class MathViewCompat {
    private static final Method DISPLAY_ERROR_INLINE_METHOD = lookupMethod("setDisplayErrorInline", boolean.class);
    private static final Method GET_ERROR_METHOD = lookupMethod("getError");
    private static final Method GET_ERROR_MESSAGE_METHOD = lookupMethod("getErrorMessage");
    private static final Field ERROR_FIELD = lookupField("error");

    private MathViewCompat() {
    }

    static void setMathTextAlignment(MTMathView view, MTMathView.MTTextAlignment alignment) {
        view.setTextAlignment(alignment);
    }

    static void setDisplayErrorInline(MTMathView view, boolean displayInline) {
        if (DISPLAY_ERROR_INLINE_METHOD == null) {
            return;
        }
        try {
            DISPLAY_ERROR_INLINE_METHOD.invoke(view, displayInline);
        } catch (Exception ignored) {
        }
    }

    static String getError(MTMathView view) {
        Object error = invokeIfPresent(GET_ERROR_METHOD, view);
        if (error == null) {
            error = invokeIfPresent(GET_ERROR_MESSAGE_METHOD, view);
        }
        if (error == null && ERROR_FIELD != null) {
            try {
                error = ERROR_FIELD.get(view);
            } catch (Exception ignored) {
            }
        }
        return error == null ? null : error.toString();
    }

    private static Object invokeIfPresent(Method method, MTMathView view) {
        if (method == null) {
            return null;
        }
        try {
            return method.invoke(view);
        } catch (Exception ignored) {
            return null;
        }
    }

    private static Method lookupMethod(String name, Class<?>... params) {
        try {
            return MTMathView.class.getMethod(name, params);
        } catch (Exception ignored) {
            return null;
        }
    }

    private static Field lookupField(String name) {
        try {
            Field field = MTMathView.class.getDeclaredField(name);
            field.setAccessible(true);
            return field;
        } catch (Exception ignored) {
            return null;
        }
    }
}
