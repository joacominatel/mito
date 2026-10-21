import Foundation

/// mito-data `fixtures/snapshot/`, copied verbatim. SwiftPM rejects undeclared resource files
/// and Package.swift is out of this lane, so the bytes live here as source.
enum SnapshotFixture {
    static let manifest = Data(
        #"""
        {
          "generated_at": "2026-10-20T12:00:00Z",
          "current_patch": "16.21",
          "ddragon_version": "16.21.1",
          "snapshots": [
            {
              "schema_version": 1,
              "patch": "16.21",
              "queue": 420,
              "bracket": "emerald_plus",
              "url": "https://data.example/schema-1/16.21/420/emerald_plus.sqlite.xz",
              "sha256": "b4d7dcf1fd531df8c3f19652a132a4b52cc8414d5f31c7b15e26f65545aaffc0",
              "bytes": 10472,
              "raw_bytes": 102400,
              "matches": 20000,
              "regions": [
                "la2",
                "la1",
                "na1",
                "br1"
              ]
            }
          ],
          "tips": [
            {
              "format_version": 1,
              "locale": "es-AR",
              "url": "https://data.example/tips/1/es-AR.json",
              "sha256": "f224457ce9d2f8c21e8811545318b91fbaae379151245cca3b1654f13ecb4165",
              "bytes": 598,
              "updated_at": "2026-10-20T12:00:00Z"
            }
          ]
        }
        """#.utf8)

    /// `emerald_plus.sqlite.xz`: Python `lzma` defaults (single stream, LZMA2, CRC64).
    static let compressed =
        Data(
            base64Encoded: """
                /Td6WFoAAATm1rRGAgAhARYAAAB0L+Wj4Y//KKZdACmURZ1gyBn4JmSIjib+MZX9x4eABpe77H+oCYAglgjhm2zP
                +gWpSoDDdQZYsrOMk1bkS6mc/F2SeInDNiFTzFGz4IELaLjqjqZkEv1gmopDdJM3CNnAxRmjz6XR9xYfsZBPLruW
                aI63yJfSrZsVUGaIgK2BQX5D2jI92P5IhRI0ybI2J8t0nNkSjso8NTQ5c317DHpi9uvyaPzHnEoDg5lxbFoj62ig
                HJOcYkNFW9t+0FcSGtZANOBHsOD/5HxYpfbI+vdBRw8KW9EuCK5wqViSwcK0Kw6659OXuy2fR9WbHICltbcXRwxN
                eEZMzjqv7ms4twUVWd3bQOmlHU0WX21+z2nAmw4DUx1A8njzSi5yFV4BcQqiigqX75AL6iUbH41o80Ualb7mxVPb
                3w2EzjOAbAXUgH0TocHqlrGIXKZUY0mxwmWpWTruyEt9sHYgdJW8l0u6KUw28i+LZru1opfE5zQYdmfuXDKcr5oD
                MuEMytCp5xlkswaI9nafbkRkmAiv8qpdjp6Gde57WVMNnkZf7ItuYI+oLSOd4HjdiY7qgl1uUTIDRSu+CMtUVGPM
                lA8GJ+likhD04pr+X3NShNjs8PlkgxjRJI1HIR72IVgcrg3SRYdVdR7RmvVDoZvpFH/mWIOt5Lhn87aK9WzLwCQv
                rRn9R87f4HPJGFSw8w3FfnWU2yoQBheWihniX4ORcT5xbRolQ9uVa304zEYz85RJSMmKXEUWbUmGAsuP6NWGeNRt
                9wN1XDrpypcOG0r5JabSrs3adUw//SFLwt2k/JcKq7hJcPXa8P5FU2Pr+BhudBrWrgenSNREGh9NRRJdkYFrY9Xf
                43u7jhQy7yGxeJUvv/Sp0wEoMAl4m1QftDA3LyXc1cjVWKmYwxG8E2Fv/E4tFSRJ972sN59ir5D4pI0W4h5TZTzW
                Er3Ssy98/rFQ6H+x3V61Es2onGKVU/9ySirv1P8qQ/dRKSXpNebZ2V2UJ/ewSLrEv6LskD5r+wMXhRbSdCjOdYSK
                Sxole1pfVFQ+zGlv3qb2ILEuAiJqqoL2TgHDzAX/Pj3OLoK+n0PbScjdkbW6SHSgHiNUo/86qDVDbEP2Fjb7EDzs
                jg1oYZd6IwMACO6lUZz5dLD6nfzFFlb33lZfoZwluKnzKpLcG949Wahm7LalNQO94/np70/q+4t5MIaZYeWrjwKQ
                /o/S/kr8iRtp06x5/EAU2UKC/lsKr13y8WZqpQI5K1+roK329VxY3U232u1N0nv1uo6dt1lg8i5ZyHmG1ku2Pn+E
                6k6rUFAolnBt8cVCTxMhelRSyOxJzZRFnTFyxKEHZy5Hyz6peghDgOph2CBDY9DkkdjCTELXxsmuvn8z34e4uucH
                qHS7Hgih8qlQVgudVq/tedHR7187o31fxtsPOClBdV0LLPJtxWL8GGiNdeLsS5RnFHE7bu30lm2CDqoB82IuT0c6
                zjGygkuajPx2hP/Ax8Sufb8gyN6dY8/qc1VilA+GHOsrAraxjoRTuOde7tXQ7K4yZ5RMljTXvL5mKx/HjWjsdhQ2
                BDZVISDJOf565FosY4Y8nDZR1K6XHNmSE2HEclzCyQhnAw7262QBVSMVkGRAJLf2yt07OyS6zHXeZbFc0n057Lsp
                vjDOebjv5qhFA9/XnMqtF2CtN10qf1X9hSZT0rjuowHc4811yuJvFCSxIosdLw2ulRGVQ1Kn+MlX0PboWPhBEmgB
                1HvzKcpizQmoglrj9QJfkBZdfNf8GZXI0kRh3aWb6tRBA1geMysNOhKD0Uy+ZWTEYJtDyJxHyLZfblO8EcTr0G/s
                HYAYvd9OP9IvCXjVj2/H3kApxwJTWtSy8qv1CvKTNZjqKnSc803JVC5cZWVB0kjXIBxXSZlhvVJDxb9lAdM+VDmT
                BjdScYM+iLb0gcOoKKGD7GlZ9dAy8y07SyG8zQZthmXzP3QOJqlY3DDoaus5ShLZgoGnj0dQYQq0P+VZ5xMZwSVx
                HoKG0v9KOlgIlAVPRvMzaMunR6irRnnHKdxszv4ocCwX9TKihnLirTbjh4tLZ5018nIFFhsZTVZcsdhfnOwVyBRQ
                oYao8djZy/9VkGWF0wXG8Qxp5orKOjQt2PXN+VMlbMvnKF/MMN3RIGlBVD70qqaBcTpULqbpEA4Zigmg1uRJuzHS
                UDxU/M6u5RZcbR6FuflwH1H+F9aAd6Hn/nVpXSeU0xjFvAyIv0q5PkmeYEWzr81Cn8sGP6pU0s9u0jUKqAA/KOkx
                KDpqHyRD/PNZRqSUZtCO06nH9gh6boIOgMRGL+YSYBWSFFDby09xGp9T4Utjq9lSIvgEafplaf5gzS0q2egwkxww
                pz9O0KwMZ+mp1hCdMeB3fRPFTBdEdhzBE5ysr8TgLyJs8/0R+qGOmkN/POwBUaTICiWf7tcfwx3MgXbsFNusngm8
                IwcBlpI+zMAQm3njywUlNw+jZmbfSuEkEqzXxQXLLpnXYiiDm3s9l8sgmVaiS76HSP1n8y7tFOQiaDzP5/AliKQK
                0tjNeIv7ktEjVTrm9d3/uN+jrVlibMfXjkqRZdv67cWMdNl2VBSPcpzCC4zvr62SPYqfMid3Vy4rL0KxtTBLWxve
                BKl7i8yj3UsITe7UDEbjAczgNNlcihmBeJ/zCfH7W5Wfmd7k2O+MXt3ds3qTBxbX88koyJ6426DAwLJ4wWJeYXmO
                7cuFawIdwIBPoqUig/atwlvaoSjrqq7mwZnoQLJFeDYnwgULfYuDHDxeYwy/cJNjz1hABURqBGL6LZHKwG2CvFO2
                ZGDjmxF9TnSEeQTEdQ0VoWeBjjQoBBE3XO3mMT6snoyXpTQZjoQd9e14278AdGFby1ZIs0No4HK1+JGTKsInoa4E
                fHn1+f9evbFTgFe1DFShf88yH6OuYOaOCteMinP1kavPCAey9WHlI8JwS/9G0T05Km5lz+M2/fFebdkgC+J2pUlY
                G7CFxSOhPITQbMYjXkygZ23h7NoylKOYA7i7CLauU2pZxoe/QO7okWGJPSi0baCCFDr9NLuf324/1ImlX5Cc7E/T
                wHjLFPu1Latjsf2jONhsb1NOvdE6LnRNlNSaBBlFWvO8gNDskPfR/WvkG/KBtYDAZdJDghMIVvds0KG082o68CRv
                tY+mrvdMMSc/gcptFymH7BLCBMW+RwPmw7OJ1p/OnYz20Pwb4JnDovO0u7ZYZx9HMFZ7RzC7/sra0gA++7aJ93J4
                MKGxAitglNjaX9y4InwfGzp282HZ8jM06RaUeJkkLDaFWAOIMR2nR61nn0t88eIHAEYmF3Z/PXR5w1Fb15hiikEP
                K2izfHyj2BP52xZwwsEgOMW/4GY9L/ze5FdZUSZYeumnJVJ6ncI7qszWrok6R4ySziOXZcF6D3Ul/Ho7N3qJW54X
                MsK7Hnu2hEiQXRpFFHumvLM62o+2UloP/5R64wnuf0+G9AuA+SWFR0tWbxJEPrX0h8WXH58G+7ZJuB/73VZTyEmt
                iIXHmu66sZWcWleyPkTMia2REE/1h/OrqmDADj79rSruwngboFRnZykI4wYzxpT4FsYhmfGRc+S35XB6p9kNMsTT
                h0lNnYmA3EKXesjcyxpa4nR8l6q72KA8HVcIz7GkDkhFchf+0sZuznMxn8v46crJR7AsvMuehKu51EsZqQmjYSpS
                sxi2zZvpL/AFGD+mevytVI3BJElhPKXfjYNI4ZEjCPpJfIKwHbXICRMhmgdXPHWLSUCyEjTmhqwXVHZi0pZpA/vz
                LoAL4FMbg/9BKzPkKAVV4J+wXdhLaESJ+fUjOiRYh9yIaLg+QcD5yMu9B5JduqAQWhlm1uLMLwWEpvk4FtJn9Epy
                qSvYP/6zkehYWdMbXuC1XmviomRW4tRMXF2YPZLX7EDaUCxsOk9mr/1SdKIu/CWwmD2J69fvDkqzSBpwpkd66WR9
                iq1EOKNJOaPjJB2MjCWDG1GXoda7dkeIWQZPrHaMWzLG5G8k/MxzAB5VcXJIJCZITW+CC0k9mILXdrBfOfRpOiSZ
                bncVna7l3ikAmd4lsz4onZsW63GzHAr9qteuY5Kub9cxQJfSV5PwOIKxJNtFyz1sLsG0zzRuXGUPlXZz0XTggmBZ
                gGHX8UbtVFYcwwk8SNCIFnixl0S4gnA4ZN3Nd16KLwb3rwHTDFxukovuDm+C7c61++zQcUKfhS3ByzR8mnpBW0m7
                OibHOjHJ+ddNe7zPE2d0PREoXwW0S7QcvyPwz7XtDdLLj+Nlh1s5efWZlUgAcv8NZaHL0o4lzrbneAOp2aTitodE
                x69C+AOt6OIRQocgx6/Prb2DV4FwIKflFaS3Q4UxDQWTves1bQU5I7f2b9kvmGK7JR2SH8O/KH9joTK7OJOb4kCM
                trBHMgpb2+bsv3V8NIFbb5xQRq4kj6qe+A5D97ySCSsW67ms3lfHBNn8Wa8aFDRpxMpfQWIhgN6QJXg4LZ4o2ePQ
                w2mFO6ja0+s9wcfes3Y/v9Mg7wDgtrYw/zwnXO/StCRcQFnCeTHrZ90LIEcNCfmMoFGnM6/aVFr1JVdGvKlTx/Ah
                LYSjXUcjnKrirQqJqJtrg0vSByR6KIOZTdDfcWH+UL9vtMCuI77lNYUNJVyZERPrW0dpUz4Vq9oiWm9I2kq+6bd1
                kXS4eZ5bvxONuiqDFz6kH9/umMgPGh/wRC8LUA1Zd/BXvhdST2ctkZUz0/QcncPpxu3xq6rNzpLL/Knn97AYMzNV
                VPwyvgZabJ3EJhqOqz7UrD+uL1itt3UBtSLEqj7RD6fA2LIAlXX+uHS/BcqpsJh1M8AMKFdlikFkqAgDRVyT+MJu
                ChmyhRX5HdHfyPnJXh3PuTwJHUK/7wNEC4sR7voZ4fDqNQRIes/X5ImFuK+54T9YDA6kpmLqemcroCcgkALYrrDx
                6cVJC8olvk4kDYRwfx+FXI5yTnS73MkCtGQKSc6Fqp0vSdb1WtROUAFs/07vD8jrvcBgbzWc+4JVdhquef6tRs66
                ctlccG9xAodi1LBpOCSBFeFtMEoDZlPmtDACiVzok83xvsRO+RGObHveppAaj26dv0uK9pHXYBtO2z/3Punsjog+
                cK5r+qGrizfTzTdxhVQ2+elbZu3/KBa4kG1NLxdkXTSK79uJjJLz2q+HBpgeji50+K/ANuK9wGc3KC3fM5h3rlg3
                oRAZf1r9utOlabtsTU//FDhK5LuDO7I39zA0E32CPn+BCmO1dR+sLcSJ9aGm+VRs3HMsJj4B4d9Br2FzTaOPrWC4
                q1/FRotq6VIJ/sUn+ZnDWxqRz7m6MHpySxgztqhekwFzV57S8itiKBZqeJixdFP7B7uNuMuN1lAm4oPcWhNvnIpm
                SByrCi2bKcIKvWY/KKKj1ocJR2YSb98Bu42pnTjFiLhqbFnsmHw0A5q0pvowOLZ209MQge9nsuBdVPxZU+IY/Wy/
                EXiM95y15jXBX0OnHH8SNWP7l1RD8Q1t7yXnpVIXSm56HZqQ2+uWxO2n7dpGJWIYVAK/jUEPpgh913hJOZsCYfL9
                YfaiC7/qgSm9PuNmvRRcXmIiBBVtvL6lCPMOL8aiFZX80YqsU2Y+O+CeERfJODoQb+MXwMosadT2LRMw/jyEuIvB
                P63zn2kxHwnIssK/6DslE3HBNHHbqDiTQ3vXrJdOljKBIJl44e0BRH2r7fnZaSsVy+mTe+NCEMjFVDHvroQAv2rA
                rucYW3a2OoGsh31jH+wEb3PMOMDqbQu7Mi/vUerfK4YIf4xlqvKrJ5fo/z20yXpBmsl3YR5BkqIncPKNd1lnsBAz
                zGhNaohLmtcLvvybYNgHULoppPxkkMC58NLKA2NNwyTnPhjqpJaJ9L9NAmtRcYb7rzddGR6/RqCH9hItaaNZT1vu
                xc1sQZ9Tl5lLwSv2h55bsUamALzxaG/B+a2qkjVEYdCJR4IUvDohcuCyB//2LAoUUxFxVC4WZy1Uz5fgkgEMYw/o
                rHXjHFUdta+/+/Z09O8ZjFtEh4GDR5odae4A4tu0GVPJdwB/iTMz89NLYxvmkFsU7VMOSoPZB/h5+1k1AlO/Vla+
                ue9HvqX/essn0gPIlMdDnyigPqkU46pVCWpKyCnvEoUGelEVDVesUgt9tSwy/GtbWLYnkKiXzQOdJRMZ44xsz97I
                YdM0ZDkylK7ZZfF6JMm4KAOm8j/BMBuUqyZUof0JIo1klWOZjzTzcoRedGxzjT0S2YXLb6jNXQ3mE0BnL0dSz8/n
                kH0rJmlTxm8Y9THTm14x6crKlKZlmpauRjLcgaqYTTdgmvjQRz3Os51nADarnUjHsVjr8dqm1TRWfCc0fgblnsGd
                Hr4eSyHV+WTOWXTLarJB19UQBmMEZDHVQoSxqEdOXH5p0gxD+GIWr8dgmeaCljh2468GFU3IMm/i/282red8qm26
                sVC9OVhVdGrdXnzIZRLt38cmcp6GpFoVMzZXwMh382j2+E9OD3yVI9lN/0xL4yQqu7L9U4ZGdsqtZZowb0Obfd2N
                o6fKxW2W7+Nk3kzUqNrKHlcpIM7IMk6eWRfxeJuXKN+DAIVu+XNRNAflEzRmPyEkuerthcxHsG0mUeiun1L3+sZn
                /Xuv7dk5LKQMU+FfmZP9JkCIhDZm9Xh30yv/vNWVW7bQgGOVzcljiIyWNPlrarWwCNOKFgFoXy92QfVUQjBXdxeF
                RQJ9BgFRfXcdyCwnlFLW3Nq2enQzM1324zKnA1im5b2yka0F45hc35ZdIL/6PSUU62ymMvTb55SlEt7+nrsAiNOu
                cIOGp5FlCmHia59nyfzDMALjBTCaHLTQu3ITLPTgXb+OEGjtPd/C+7DCpnW+D3R93657mJnP7wzJxJ6qajKqF416
                i8oOmOrd+cd9mOWYPdAnVpkdJ73OadmuaYbIOALZJzIv4tsX29xuWXmUEjqUCUgU6yw5bMrhzmRZ0QbjKJes3p7i
                EjtAKUK8E4MClpV3E4cTCDfSGHqVbk20yPl8mey5UAe4Mi8IplD4rSaNjEREUxeeAWMJyT+QoIKhzIgJoJLlg1y0
                Q/KMjogKo3QEak619wBsxRRuPKxgsNt15ZMT1iiCjiwbpdKdmSolWQTpZ+RkBFdEQ92h8yvALhRcOMbWRco90KRr
                QliSnuiWGI0g4wp4J+7bxPfzCeJHicYa6d0Wkrb5/y1buH3VdTbpwPVp7MrHDX1LwqqSs2r6PvH3QpOdD4WLpkNT
                LFSMszh1imqYuWAqbSOWFHCGRNJHO2aGDUYsTjg4GimGnyGTCWKHG1ytUZGtoCOD5XZu3Ytz3rKTyxWy5HsGWIWH
                kFpvBOZJ2cMcxt94YWJ/tvjCdFAn1L19ym5wxztQ/Lgjz3FOBMiu55zzyQGWCUKYmfU7uL9P/6jdwjPUUI41dJAI
                3EDpfN70lhqWKAgV0kPS0plZbWafcA3Nx5A+GjmCNTkHtBUM7SiDVG0dwthcyNq2XJgCg819rLtJpKoKTCiLXD7T
                EGGheSCu4TbtTFVeQ5MkJN91Y5Ydgp3K+E/ef/KQOw2m8nePpDKtCd/84y8+JK9UTlaIuDJtV8AU/WiBvjCZ+9Su
                CL11JzRENYlM3neB/dc0yNPHWnjhUsGX64XK+JgrXoGExv5ok+CSUFxCCwK3x5E/tN4cvrfH1Hv3QWrN79ptBHjM
                eJm8K1JpCQSlO0ob2j5MbIAPA52XQhBz7E1xk/O6ClsYTR5DNaMZUis3/cJwxtYNlqgCYeb/h7nDl3iwS+Sp6zfO
                s2gZuOl8Q+B+OgKaiLwyBM6pjGvLfbo1brOM27ZYNjSuXU3iTlfjTz28vUc/Zem8OqzBQ1UlAWDyBg1YoZW7xlxg
                31nSqGI4GbUoavkH2Joyb+UAAfIlsMxWSLNJ3ySRQC3LGTWU3kbj+8UvcHUmihO6q9f3DT+WgeEEKyWgmbJABPZE
                Vd8NiWVTk5PyW2vPq0LJAjdKN+kI5E9nkDqdTkjG8ZA5BlEp2PTXFNeF84Yr6IjeY9HSIV+vIbEwpYpI3eNYyHKT
                JjradcILBrTOO927oRgIIzyz1/cZqinj2/z45aVnc5gQPMPbG0wk+/qC0ZpyqMSqkW9eN1aRini9QsbtgYKnlY2v
                IIhdxBuCHgmo4+CGoIGrlBG4nba8CP46lAFp9v24XKT97aJiIsKair8mPSSn+Sht7uaqWt53od0jSDZbyA1aPgBs
                74/uWp0wmj5jya7UJIxU8KzX6YDw2vDxhchZWYb23PlyIByWw6wnHYsD/KiTcndGUxoiJJ09CuwB+zuo52Lr6zQn
                YRAoroRcAz2x+h9S1hR6ofrkixgzEb2Jw+m8rD13XToVvwu6h3fieMXgsO5cDOcwO1DTXUUYHxfwEogwMq0K7Cyz
                63PrtIQ7BvcGb52ZbO59wlK2D1Fmsk/ohzCH6YVjJ24QYcibgM2xGAU42kffCBgptjm0KsttY6tv9q5F050x53ya
                +KYN2YgPAXtHkkVl24Pzf47q3Zx9qcbE+djwFz9ijwAbDbkbxJr1y6SyINEVZLW+8/60nYKb9rKIDjeXIvwhWt5G
                rYQApbxq0n2tpNxPWtJs5zehbarNuna7wgON1c7cUvRvj5gnPazQNh+NFbKYO2V/EzQQi5BxOkVcjKyaB4gzKKa5
                CHThU96wDKLg3zq0lnbFe6xAzHYlnC1f9jDZDm2w584wXzmxCekn8J8S3ckSbfabzB3duRD5jUcq55CB1Fge7aqp
                l+7Ti6Ug4Q4rNvA8++EH+H1k1JcAwJV2ZKVnvUIYB7RjTYcaHszYULFSbqizK++1IJEgHLVwpy9suSQkhLVgvI1/
                tPENwE1tXfJCmOQRNGwxGHw8gq9tjQ5uI6yWSx6eZB9Mt+Zu1HJm2aViXOKiTcBpd4ycNw6l7bAQr8vWs3VOkE9Y
                0DujDjD19c/i1TuxvR1q5PsUMoH5B1+CP7MzSLqvsgUJZeq8nDCFwBJIQxuidhBDVjqIpfdV3fi1sdk51nU6++0A
                8hecEp0umpbF92CbkBr62qWqoqtv8yRSxTp04oBQAasDEuJpOcsAJfpRi7CsW3sLfyjQLFaRZ75SZP7pJbgf5xQl
                t+zf5SdToxJ7JMqvl258MBRtrIv0qZXwdveh4cRAXL4FkoPQr81h8aMG4TVRa8EuSlCkLYOf4EiO3a8ASNV/zdtb
                gGWgf/iDQYZI3LFAW60/dGE+9DG90FHlZxiZS+ZJnczSwH/ClsMYzSlMamH+KOitkPlqtNScwMMxXcwVpqWkXP56
                3LVX5DKkgRNGQuBVgAp8vTlB9jJqag6lkhccM+lAFOgp0Kff4SWuksAz+iL7GQseXW7h1qIkqvhsv1z+opBtErSM
                9V1xHtzT0/aDvwT25NC4fFsmjkWKx1LX28lf1Z8oJTrV5UCSGC9AP6CbS+KZmzRncHwtvdu8Dalotn5gOTbFYTfc
                4RW+R7//Slr0zgxyQnqSJFjWR0B+4SEDocQCeS+R4Dyw+76BcSYOVF1f1ieWZGiVlVcrsX27qjGkEq2V0f7AKRD5
                QBTTLMgHbiukiZWIQL/WgFfSmcYwUuISLQlzc/MReHtWjzsyN1R4bqBy0mJhMbyLCS3ROht3YohqCOJx9Yzh/rY/
                0NmsBuYp3oelQS56OFk0wE733R+xars/wKAkdh6R4aEKFC7tPx90tobf1S4faoAoSOfgkG5CJn+skv9uP1SBzeoV
                Js7FXyplM619EFjaAkPQwCC0+vHbRrY92CPfWQgrENRaGpNCXRmgVyrXH5Vog6X8MsW18F0vXI4Dzv1YTNWgxPKb
                tY4jwileDaTDPz3r+No4h0fMMXa+bxIHGOGGA4WYX0uikHrWy0VJYCQdXhBDS6hjigRtCJloPt7P5nOpMJbI6BLZ
                OVELrVfBjHk2o965YSSbcAl7xNQ4nkr//rPnMYOkVK9LsmnlBHEQ23qCRuo5bR9K4CXWZPtPaHKaEYKref1qM3hh
                oU8TY+k48vXugs/VKwvDpsA8nqDHd2TaWtYkWCtCNiyf18m0l/73XHwrRznsxTcro0SuprHOUrL0s8LjihwYAG1N
                I4xsFIX9UMiqIlH8MdSKkCHK26+zwGK/UDn7O1T2hYupxD1l0ykkZMPRewWXrvAZWWnHzFR8TWHV0kZ57wIBD0PM
                dCKVjl/5Tkw60I18YYP1aAo7Nr6+Shl3410acUpLaOtEYjXtfrRaCNrmVrXj6CS2Jvdltl0V02soeKe78vO91ZSZ
                iNCGx5/uIdRqxEccvFTlwJ4ALLyj9+ILVHEaS9Ric6HXtIq7UdnpT7SeiS+oQHv875VfW738HtRExFbj4f5J95SE
                hA7y45GxoP2K3bMjyGoffpPHoLw73zlNvgaQR1LNIkpj6fkM0WbMEinA9Mh6fVs7BV5P0P71dOiGySk3iI9JpBTK
                I3zoYd+3o6kU2pXLkiRQ6X2Xs0K0FAvJ35ueIoPfMV4kufe9sQfwxpYwj/tAUzh24Irm7CIFfuL2jdYAOjDW4Ap4
                tsmziilrku1OY6jZD6YKZhohswG6nl+yUp8UzsVJsXZ02usKtL4Jga8rrx/IiGzMDNNKZUpGgzuUPezYcFbe4WO2
                6sxFS8BcaRu6GSpYTHeJORxDF1fI/GRLiuRXoZB5l+A4N8XpuQRHhZWsqsiscvjS0HKDiw+iQx/OKhyOZP2q0OZ8
                gQKKX9e1HwxPQJSI2pu4df8kPNxCq1WaDypYGfRrhKtanZiz+Lp+bOWgTj95S1DnfRtqbykf35ffovEPq464iUrv
                48A5iHjJu7tfe6UAc2r16g/sU6JzM0XdWf+ZDfmuMKhEHihTF5IpXwSA6PhfaEc8i/NiYE02CaUlv0LIH/yCdVwJ
                D/v8VHtZP2mAZqPsZkWT/GzMqYeiYyiaIHPFpUlXVrnxTHO4gEHb9s1Agg21BAcnx66S2L+DoHnWY+YklCk1oXRh
                mCr0fFYciTVF0C/JaWUkBc8bDhnPLTmdEIvspm6eGwabHeBMOgEFIjhxECmpZo73HflXuxx6lGt41po2BD+SmCW6
                XJFZrps3HjqckzSjRVFKGRGLAw8W1TbcG88dTAqKbVBQYZ1BdiOV8bZiQvjUP3phkhyrZQQMZe8OzFWk1+s5cPUq
                34J4JH0zz+DWl3xdYAiyfBLCOQNFLbbcPcx4FfBWwkskGOaujEDgrHoBdG0y/HMLDzbiT82xrfG8qaEXdd4GuWww
                GAEUAK6eDazUnMc+JShGXqI7CLuIGsMeRl5os0MLmpcftAnlcQyB2oWyMIA4xeT91WUMIEHqoECNvXrxsEHhiKBZ
                XfqYGvD8+mkR47WeIrWXhvBdm05Y6CCnK0l9eSKhoc83lqYx52QMIFEv5ZdHXvI24J23u5H3YQURqkopMfEyIaO5
                R7BS1V4UZQMkVa4oaMeCTX0NuGcNEldaNtcnKZRHhHcVNtNzjQfidN1C0fE36L5umV0Q0YIga/0ivWyX99loSO70
                FTNzaCINf87aQvD3WhHoQM4wdd0nWd34oqkz52WJf9zezPdp4W/PRTKUfx12aduw5iKZwkcQo4mzDJ/xFIDczGPN
                nF+hSiD937jTgxjY56oKI/MASE+5uXOz19Bw0gSAfe9BAe6hPIyeIM6Ek4cEvDGDJVdWlhst+LvMzNThKUlYQLVu
                2Je9QVELewlR1HaML/I0suR9K6J3MWE9W4q+oDoQLGW0EUNatcFgXTrYiJOv6hvBfMtazYway2e/SB7djGAJFrKg
                PxqgBdJJthEDJor0u5NN3jga/NX9rhdRcIA7YtIaLnGkT3yuScTE0426NvwWgrfsYb4ZLSwIZmqg/F5ULP26G/Yc
                Cu6yFKhDLS25aX93RJjv7btuJKgu/ZJLkZbwzjXahS2OvTShVIEUqCu8OB2bYNEdXHAMf+7eYINTZ624EMPa7gCG
                4SHcgaNA45xW/P7lY3/fLWqw2WM0oAQKidqEBv41B8JWgtfokQhyh7CTqor4VdKh4iH2Zd23RV6rGmd1WHsmiRJ5
                qKrlcj6ipciR6juHyy4F+j8rthOBirbaAGCajuPAmIO4jWRurMhrythyun2D35nduqyrN/TpK4MqKuFh24cuc/p/
                5oG+kehfpEJn/r4jCDwaw9v56WTVmerbY0eT5CRCIytnaQSNt1909jX9XNN2S8abAkfaM7x57CV7NsGu5DfLiDDT
                x2HbLh9Ci803tddSFchVKs0zD2T/pDEFURD2HJTALAzNpWy0+Zc6pqagq5W4MBBzNEdmtUfda+o7jeBOEi9Rt/uY
                n3epxJvEv3MWkUS/9rV47GEIt2h9QkKndpvMBRicMuUmIo//jNHXqe13Cvx1cH137XM++oUnt1d3Trqnr1eHtkpo
                E2HfRYL1ERRHVuzPZgS5gs7L35mpguUeKY8jiN19ispgoqftbwq8K6qd4IwvWoWiryJqGd57HSDsLV+fdLVsrlEL
                W88Ts3OT6h4iP9QRDoUbQpe7QcXb6W7KtyEQlFvuYjP87w/AwpUlF0O4d1+eRbS9eYPgb4tg5D9VW8kZB31n1sv7
                6nLkYMWbxa6i+8R1N9GdXJGCI+MC72QqmHvOW+ZC0ahVoN1kLDD7jKUxHj9Sgozz+Ler5vzF8P0sFhwh8uLKrAVf
                cmvH1G7iHCNmTWSaIbiCn+vT2PMcuJhPYpwU9mWbMor6nPD3fDPyFYb+1y6RV8xx40POtI7GuQLecyA13L6TXLzu
                oKI41q9W0f0SVSMa41cDx1ghS+wDzmDHMcBiIX9nDmMHhAY2jr2B8Wc2LCsc8Xvr+HDfLqT035bBVMOVsp6VPZsh
                nVHxP3DbsHNoCpYPMy5ndX2Qgg7FUA8JrKzSzuneQ/WPJ8HJHrggBcsbO1f93v0/4dpxwavgRNWBAJrKNn8zBzXw
                bueEKuckw0tQTksnngEYXzWeIMfuV3PNStZBcMVQDyMVyDWbnvfGwL2RYzqJZf2VMBTSQC1+01VvdnwIAHuBH6K/
                lPXQFTsVJc2u1l9OM9gkXTxSFGQUvnzl+ZWVi6ZC8jJFAYI2AFBJAO7stEWhckwuy2KkZu5UeNZJ2QyzFFBvq4FZ
                1GngB2c3Yyt4UAXb3dRgXSLKMmJJOsGDfDFBTTcsbmxLsnhkVuD5/+FG/YmGHHPkrXoEtG4e8WIBzP4MF6bhfmfF
                XMMUC+EPtlMczOHVHFfUiJDJSYkNU9OlRg2JCRCuw0a2+AjhAvO37snIQaxGio1bEyKwnCIEyNLqW9ELr18WKc3m
                56F43F381gEcrLYOS2tYTBnDdzlC4k8IBg4L/o1Ja+/aW0IbqeHxKwEZvU2s4mBZfi5gGr7UyV9WPiguhfVegui1
                9FyZXyKADssapLnUsitEFTDq4UAKNZNIN+p+wQ45HZ4by6nX/Gr4PQqnJOVcqTQsRZjbXDg7H0uEUBJ1BNvuwaIK
                kklPt5CvGQ19IVUO0xnY2shZRkaHUOAs0n2NHiKiL5RKKXCWpxyTfYE6CzrFmolgh2SHSIz+SlD+pWpcs8Nt+UAl
                0Y/ykmoZLuBxkDIcCFIxYBqnzv52ReZQlko4I3Y2J2Wn9xaD6tpQmFZPFM6T7FvWlDNl6ExGby2PVws3LvF8jvVe
                65o83R9kE61T+t4XRlsvXH9fHRSp3QixkoXNJQQ4tr4BGPJzTNCJ39TXlKdcdq5DcSn9ZFF1Fc/Aw5FD2uoP96FM
                wB6xyBVZsjBephj4R2IzMKupuAbuqZ2ZEdrRIQDAvyOnvxkVkmSZHZq+X8gACbl42QhAPIWbb5hjx+Kj/ejawNos
                6Yjfw1ynXtd0m4FSkcHr3s+k+P+3Lx6G6Cvktim6d/xTtez8Z99Tz47ZPH08nJzykgOhvYrGmzptoXe7oVYMOD4P
                mNO7QBF/W1o2FEOkWGOLAuPe8p0KcqWSu9UU0e2BhQKimcM/S0dk+wZxSe8n52ZwBlYmNDMdoVPMxaIffjXSETnB
                GWjCrbMQt1AKAAAASvGobWE9/HYAAcJRgKAGAMTBffixxGf7AgAAAAAEWVo=
                """, options: .ignoreUnknownCharacters) ?? Data()

    /// `emerald_plus.sqlite`, the decompressed file, by digest and size.
    static let sqliteSHA256 = "1d1ee147a49a8572a70e77deb734ca69277d31a3736c866f3c43ac265ddfd927"
    static let sqliteBytes = 102400
}
