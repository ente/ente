# Logger Filter Feature Usage

The log viewer now supports filtering logs by logger names directly through the search box, without any UI changes.

## Search Syntax

### Basic Logger Filtering

- `logger:AuthService` - Shows only logs from the AuthService logger
- `logger:UserService` - Shows only logs from the UserService logger

### Wildcard Support

- `logger:Auth*` - Shows logs from all loggers starting with "Auth" (e.g., AuthService, Authentication, AuthManager)
- `logger:*Service` - Not supported yet (only prefix wildcards are supported)

### Combined Search

- `logger:AuthService error` - Shows logs from AuthService that contain "error" in the message
- `login logger:UserService` - Shows logs from UserService that contain "login"
- `logger:Auth* failed` - Shows logs from loggers starting with "Auth" that contain "failed"

## Quick Access from Analytics

1. Navigate to Logger Analytics (via the menu in the log viewer)
2. Tap on any logger name card
3. The log viewer will automatically populate the search box with `logger:LoggerName` and filter the logs

## Implementation Details

- The search box hint text now shows "Search logs or use logger:name..."
- When logger: syntax is detected, it's parsed and converted to logger filters
- The remaining text (after removing logger: patterns) is used for message search
- Multiple logger patterns can be used: `logger:Auth* logger:User*`
- Clearing the search box removes all filters

## Benefits

1. **No UI Changes**: The existing search box is enhanced with new functionality
2. **Intuitive Syntax**: Similar to GitHub and Google search operators
3. **Quick Navigation**: Tap logger names in analytics to instantly filter
4. **Powerful Combinations**: Mix logger filters with text search
5. **Wildcard Support**: Filter multiple related loggers with prefix patterns
