## Icons

Ente Auth supports the icon pack provided by [simple-icons](https://github.com/simple-icons/simple-icons).

If you would like to add your own custom icon, please open a pull-request with the relevant SVG placed within `mobile/apps/auth/assets/custom-icons/icons` and add the corresponding entry within `mobile/apps/auth/assets/custom-icons/_data/custom-icons.json`. Please note icon names may only contain lowercase characters.

Please be careful to upload small and optimized icon files. Icons exceeding 20KB will not be accepted.

Note that the correspondence between the icon and the issuer is based on the name of the issuer provided by the user, excluding spaces. Only the text before the first dot "." or left parentheses "(" will be used for icon matching. e.g. Issuer name provided: "github.com (Main account)" - Then "github" will be used for matching.

This JSON file contains the following attributes:

| Attribute  | Usecase                                                                                | Required |
| ---------- | -------------------------------------------------------------------------------------- | -------- |
| `title`    | Name of the service.                                                                   | Yes      |
| `slug`     | If the icon's SVG file has a name different from the `title`                           | No       |
| `hex`      | Color code for the icon                                                                | No       |
| `altNames` | If the same service goes by different names or has different instances (e.g. Mastodon) | No       |

Here is an [example PR](https://github.com/ente/ente/pull/9121).
