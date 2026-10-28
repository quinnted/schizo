@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # schizo is a console tool and its output is for a person at a console.
        'PSAvoidUsingWriteHost'
        # internal helpers, not cmdlets. a -WhatIf on every helper would be
        # noise; the scripts have -Audit instead.
        'PSUseShouldProcessForStateChangingFunctions'
        # Get-StoreApps, Get-InstalledApps and friends return several things.
        'PSUseSingularNouns'
    )
}
