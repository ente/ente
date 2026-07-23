#include "include/local_auth_linux/local_auth_linux_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
#include <string.h>

#define LOCAL_AUTH_LINUX_PLUGIN(obj)                                      \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), local_auth_linux_plugin_get_type(), \
                              LocalAuthLinuxPlugin))

static constexpr const char* kChannelName = "ente.io/local_auth_linux";
static constexpr const char* kPolkitBusName = "org.freedesktop.PolicyKit1";
static constexpr const char* kPolkitAuthorityPath =
    "/org/freedesktop/PolicyKit1/Authority";
static constexpr const char* kPolkitAuthorityInterface =
    "org.freedesktop.PolicyKit1.Authority";
static constexpr const char* kPolkitActionId = "com.ente.auth.unlock";
static constexpr const char* kPolicyAssetPath =
    "/usr/share/enteauth/data/flutter_assets/assets/polkit/com.ente.auth.policy";
static constexpr const char* kFlatpakPolicyAssetPath =
    "/app/share/enteauth/data/flutter_assets/assets/polkit/com.ente.auth.policy";
static constexpr const char* kBundledPolicyAssetRelativePath =
    "data/flutter_assets/assets/polkit/com.ente.auth.policy";

struct _LocalAuthLinuxPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(LocalAuthLinuxPlugin, local_auth_linux_plugin,
              g_object_get_type())

struct _LocalAuthLinuxPluginClass {
  GObjectClass parent_class;
};

static const gchar* string_or_default(const gchar* value,
                                      const gchar* fallback) {
  return value != nullptr && value[0] != '\0' ? value : fallback;
}

static gboolean is_flatpak() {
  return g_getenv("FLATPAK_ID") != nullptr ||
         g_file_test("/.flatpak-info", G_FILE_TEST_EXISTS);
}

static gchar* policy_asset_path() {
  if (is_flatpak() &&
      g_file_test(kFlatpakPolicyAssetPath, G_FILE_TEST_IS_REGULAR)) {
    return g_strdup(kFlatpakPolicyAssetPath);
  }
  if (g_file_test(kPolicyAssetPath, G_FILE_TEST_IS_REGULAR)) {
    return g_strdup(kPolicyAssetPath);
  }

  const gchar* appdir = g_getenv("APPDIR");
  if (appdir != nullptr && appdir[0] != '\0') {
    g_autofree gchar* appimage_path =
        g_build_filename(appdir, kBundledPolicyAssetRelativePath, nullptr);
    if (g_file_test(appimage_path, G_FILE_TEST_IS_REGULAR)) {
      return g_strdup(appimage_path);
    }
  }

  g_autofree gchar* executable_path =
      g_file_read_link("/proc/self/exe", nullptr);
  if (executable_path != nullptr && executable_path[0] != '\0') {
    g_autofree gchar* executable_dir = g_path_get_dirname(executable_path);
    g_autofree gchar* executable_relative_path = g_build_filename(
        executable_dir, kBundledPolicyAssetRelativePath, nullptr);
    if (g_file_test(executable_relative_path, G_FILE_TEST_IS_REGULAR)) {
      return g_strdup(executable_relative_path);
    }
  }

  g_autofree gchar* cwd = g_get_current_dir();
  g_autofree gchar* cwd_path =
      g_build_filename(cwd, kBundledPolicyAssetRelativePath, nullptr);
  if (g_file_test(cwd_path, G_FILE_TEST_IS_REGULAR)) {
    return g_strdup(cwd_path);
  }

  return g_strdup(is_flatpak() ? kFlatpakPolicyAssetPath : kPolicyAssetPath);
}

static FlMethodResponse* error_response(const gchar* code,
                                        const gchar* message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message, nullptr));
}

static GDBusConnection* system_bus_connection(GError** error) {
  return g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, error);
}

static gboolean polkit_action_exists(GDBusConnection* connection,
                                      GError** error) {
  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      connection, kPolkitBusName, kPolkitAuthorityPath,
      kPolkitAuthorityInterface, "EnumerateActions", g_variant_new("(s)", ""),
      G_VARIANT_TYPE("(a(ssssssuuua{ss}))"), G_DBUS_CALL_FLAGS_NONE, -1,
      nullptr, error);
  if (result == nullptr) {
    return FALSE;
  }

  g_autoptr(GVariant) actions = nullptr;
  g_variant_get(result, "(@a(ssssssuuua{ss}))", &actions);

  GVariantIter iter;
  g_variant_iter_init(&iter, actions);
  while (true) {
    g_autoptr(GVariant) action = g_variant_iter_next_value(&iter);
    if (action == nullptr) {
      break;
    }
    g_autoptr(GVariant) action_id_value = g_variant_get_child_value(action, 0);
    const gchar* action_id = g_variant_get_string(action_id_value, nullptr);
    if (g_strcmp0(action_id, kPolkitActionId) == 0) {
      return TRUE;
    }
  }
  return FALSE;
}

static gboolean check_polkit_authorization(GDBusConnection* connection,
                                           gboolean allow_user_interaction,
                                           GError** error) {
  const gchar* unique_name = g_dbus_connection_get_unique_name(connection);
  if (unique_name == nullptr || unique_name[0] == '\0') {
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                "Unable to determine the app's system bus name.");
    return FALSE;
  }

  GVariantBuilder subject_details;
  g_variant_builder_init(&subject_details, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&subject_details, "{sv}", "name",
                        g_variant_new_string(unique_name));

  GVariantBuilder details;
  g_variant_builder_init(&details, G_VARIANT_TYPE("a{ss}"));

  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      connection, kPolkitBusName, kPolkitAuthorityPath,
      kPolkitAuthorityInterface, "CheckAuthorization",
      g_variant_new("((sa{sv})sa{ss}us)", "system-bus-name",
                    &subject_details, kPolkitActionId, &details,
                    allow_user_interaction ? 1u : 0u, ""),
      G_VARIANT_TYPE("((bba{ss}))"), G_DBUS_CALL_FLAGS_NONE, -1, nullptr,
      error);
  if (result == nullptr) {
    return FALSE;
  }

  g_autoptr(GVariant) authorization = nullptr;
  g_variant_get(result, "(@(bba{ss}))", &authorization);

  gboolean is_authorized = FALSE;
  gboolean is_challenge = FALSE;
  g_autoptr(GVariant) result_details = nullptr;
  g_variant_get(authorization, "(bb@a{ss})", &is_authorized, &is_challenge,
                &result_details);
  return is_authorized;
}

static gboolean is_cancelled_error(GError* error) {
  if (error == nullptr) {
    return FALSE;
  }
  g_autofree gchar* remote_error = g_dbus_error_get_remote_error(error);
  return g_strcmp0(remote_error,
                   "org.freedesktop.PolicyKit1.Error.Cancelled") == 0;
}

static gboolean can_authenticate_with_polkit() {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) connection = system_bus_connection(&error);
  if (connection == nullptr) {
    return FALSE;
  }
  return polkit_action_exists(connection, &error);
}

static gboolean authenticate_with_polkit(gchar** error_code,
                                         gchar** error_message) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) connection = system_bus_connection(&error);
  if (connection == nullptr) {
    *error_code = g_strdup("polkit_unavailable");
    *error_message =
        g_strdup(string_or_default(error != nullptr ? error->message : nullptr,
                                   "Polkit is not available."));
    return FALSE;
  }

  if (!polkit_action_exists(connection, &error)) {
    *error_code = g_strdup("setup_required");
    *error_message = g_strdup(
        "The Ente Auth Polkit policy is not installed on this system.");
    return FALSE;
  }

  error = nullptr;
  if (check_polkit_authorization(connection, TRUE, &error)) {
    return TRUE;
  }

  if (is_cancelled_error(error)) {
    *error_code = g_strdup("authentication_canceled");
    *error_message = g_strdup("Authentication was canceled.");
  } else if (error != nullptr) {
    *error_code = g_strdup("polkit_error");
    *error_message = g_strdup(error->message);
  } else {
    *error_code = g_strdup("authentication_failed");
    *error_message = g_strdup("Authentication failed.");
  }
  return FALSE;
}

static FlValue* setup_status() {
  gboolean polkit_available = FALSE;
  gboolean policy_installed = FALSE;
  g_autofree gchar* error_message = nullptr;

  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) connection = system_bus_connection(&error);
  if (connection != nullptr) {
    polkit_available = TRUE;
    policy_installed = polkit_action_exists(connection, &error);
  }
  if (error != nullptr) {
    error_message = g_strdup(error->message);
  }
  g_autofree gchar* asset_path = policy_asset_path();

  FlValue* status = fl_value_new_map();
  fl_value_set_take(status, fl_value_new_string("actionId"),
                    fl_value_new_string(kPolkitActionId));
  fl_value_set_take(status, fl_value_new_string("policyAssetPath"),
                    fl_value_new_string(asset_path));
  fl_value_set_take(status, fl_value_new_string("polkitAvailable"),
                    fl_value_new_bool(polkit_available));
  fl_value_set_take(status, fl_value_new_string("policyInstalled"),
                    fl_value_new_bool(policy_installed));
  fl_value_set_take(status, fl_value_new_string("isFlatpak"),
                    fl_value_new_bool(is_flatpak()));
  if (error_message != nullptr) {
    fl_value_set_take(status, fl_value_new_string("errorMessage"),
                      fl_value_new_string(error_message));
  }
  return status;
}

static void local_auth_linux_plugin_handle_method_call(
    LocalAuthLinuxPlugin* self,
    FlMethodCall* method_call) {
  (void)self;
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "isDeviceSupported") == 0) {
    g_autoptr(FlValue) result =
        fl_value_new_bool(can_authenticate_with_polkit());
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "getSetupStatus") == 0) {
    g_autoptr(FlValue) result = setup_status();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "authenticate") == 0) {
    g_autofree gchar* error_code = nullptr;
    g_autofree gchar* error_message = nullptr;

    if (authenticate_with_polkit(&error_code, &error_message)) {
      g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    } else if (g_strcmp0(error_code, "authentication_failed") == 0) {
      g_autoptr(FlValue) result = fl_value_new_bool(FALSE);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    } else {
      response = error_response(
          string_or_default(error_code, "polkit_error"),
          string_or_default(error_message, "Authentication failed."));
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void local_auth_linux_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(local_auth_linux_plugin_parent_class)->dispose(object);
}

static void local_auth_linux_plugin_class_init(
    LocalAuthLinuxPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = local_auth_linux_plugin_dispose;
}

static void local_auth_linux_plugin_init(LocalAuthLinuxPlugin* self) {
  (void)self;
}

static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  (void)channel;
  LocalAuthLinuxPlugin* plugin = LOCAL_AUTH_LINUX_PLUGIN(user_data);
  local_auth_linux_plugin_handle_method_call(plugin, method_call);
}

void local_auth_linux_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  LocalAuthLinuxPlugin* plugin = LOCAL_AUTH_LINUX_PLUGIN(
      g_object_new(local_auth_linux_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), kChannelName,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
