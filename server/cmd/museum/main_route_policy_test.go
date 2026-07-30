package main

import (
	"go/ast"
	"go/parser"
	"go/token"
	"strconv"
	"strings"
	"testing"
)

type routeRegistration struct {
	group  string
	method string
	path   string
}

func TestStorageContentRoutesUseStorageAPI(t *testing.T) {
	routes := collectRouteRegistrations(t)

	for _, route := range routes {
		if route.group == "privateAPI" && requiresStorageAuthBlock(route.path) {
			t.Errorf("%s %s is registered on privateAPI; use storageAPI", route.method, route.path)
		}
	}

	for _, prefix := range []string{"/user-entity/", "/contacts", "/attachments/"} {
		if !hasStorageRoute(routes, prefix) {
			t.Errorf("expected %s routes to be registered on storageAPI", prefix)
		}
	}
}

func collectRouteRegistrations(t *testing.T) []routeRegistration {
	t.Helper()

	fileSet := token.NewFileSet()
	file, err := parser.ParseFile(fileSet, "main.go", nil, 0)
	if err != nil {
		t.Fatalf("failed to parse main.go: %v", err)
	}

	httpMethods := map[string]bool{
		"GET": true, "POST": true, "PUT": true, "PATCH": true, "DELETE": true,
	}
	var routes []routeRegistration
	ast.Inspect(file, func(node ast.Node) bool {
		call, ok := node.(*ast.CallExpr)
		if !ok {
			return true
		}
		selector, ok := call.Fun.(*ast.SelectorExpr)
		if !ok || !httpMethods[selector.Sel.Name] {
			return true
		}
		group, ok := selector.X.(*ast.Ident)
		if !ok || (group.Name != "privateAPI" && group.Name != "storageAPI") {
			return true
		}
		if len(call.Args) == 0 {
			return true
		}
		literal, ok := call.Args[0].(*ast.BasicLit)
		if !ok || literal.Kind != token.STRING {
			return true
		}
		path, err := strconv.Unquote(literal.Value)
		if err != nil {
			t.Fatalf("failed to parse route path %s: %v", literal.Value, err)
		}
		routes = append(routes, routeRegistration{
			group:  group.Name,
			method: selector.Sel.Name,
			path:   path,
		})
		return true
	})
	return routes
}

func requiresStorageAuthBlock(path string) bool {
	switch {
	case path == "/files" || strings.HasPrefix(path, "/files/"):
		return true
	case strings.HasPrefix(path, "/trash/"):
		return true
	case path == "/comments" || strings.HasPrefix(path, "/comments/"):
		return true
	case path == "/reactions" || strings.HasPrefix(path, "/reactions/"):
		return true
	case strings.HasPrefix(path, "/social/"):
		return true
	case strings.HasPrefix(path, "/comments-reactions/"):
		return true
	case path == "/collections" || strings.HasPrefix(path, "/collections/"):
		return true
	case strings.HasPrefix(path, "/collection-actions/"):
		return true
	case path == "/memory-share" || strings.HasPrefix(path, "/memory-share/"):
		return true
	case strings.HasPrefix(path, "/cast/"):
		return true
	case path == "/users/locker-usage":
		return true
	case strings.HasPrefix(path, "/user-entity/"):
		return true
	case path == "/contacts" || strings.HasPrefix(path, "/contacts/"):
		return true
	case strings.HasPrefix(path, "/attachments/"):
		return true
	default:
		return false
	}
}

func hasStorageRoute(routes []routeRegistration, prefix string) bool {
	for _, route := range routes {
		if route.group != "storageAPI" {
			continue
		}
		if route.path == strings.TrimSuffix(prefix, "/") || strings.HasPrefix(route.path, prefix) {
			return true
		}
	}
	return false
}
