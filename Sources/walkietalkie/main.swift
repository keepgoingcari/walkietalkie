import Foundation

var args = Array(CommandLine.arguments.dropFirst())
if args.first == "--" {
    args.removeFirst()
}

if args.isEmpty {
    WalkieTalkieApp.main()
} else {
    let code = WalkieCLI.run(arguments: args)
    Foundation.exit(code)
}
